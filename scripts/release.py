"""Transactional static-site publication and rollback using the AWS CLI.

Upload and verify a complete immutable release before changing the entry point.
Never deletes release data. Any post-activation failure restores the prior HTML.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from release_manifest import create, verify, validate_release_id
from smoke import check_site


class AwsCli:
    def __init__(self, bucket, distribution):
        self.bucket, self.distribution = bucket, distribution

    def run(self, *args):
        result = subprocess.run(["aws", *args, "--no-cli-pager"], check=True, text=True, capture_output=True)
        return json.loads(result.stdout) if result.stdout.strip().startswith("{") else result.stdout

    def exists(self, key):
        result = self.run("s3api", "list-objects-v2", "--bucket", self.bucket, "--prefix", key)
        return any(obj["Key"] == key for obj in result.get("Contents", []))

    def upload(self, directory, prefix):
        # Write the manifest last: its presence means upload completed.
        self.run("s3", "cp", str(directory), f"s3://{self.bucket}/{prefix}/", "--recursive", "--exclude", "release.json", "--cache-control", "public,max-age=31536000,immutable", "--only-show-errors")
        self.run("s3", "cp", str(directory / "release.json"), f"s3://{self.bucket}/{prefix}/release.json", "--cache-control", "public,max-age=31536000,immutable", "--content-type", "application/json", "--only-show-errors")

    def download_release(self, prefix, directory):
        self.run("s3", "cp", f"s3://{self.bucket}/{prefix}/", str(directory), "--recursive", "--only-show-errors")

    def download_current(self, path):
        self.run("s3", "cp", f"s3://{self.bucket}/index.html", str(path), "--only-show-errors")

    def activate(self, path):
        self.run("s3", "cp", str(path), f"s3://{self.bucket}/index.html", "--content-type", "text/html", "--cache-control", "no-cache,no-store,must-revalidate", "--only-show-errors")

    def invalidate(self):
        response = self.run("cloudfront", "create-invalidation", "--distribution-id", self.distribution, "--paths", "/", "/index.html")
        self.run("cloudfront", "wait", "invalidation-completed", "--distribution-id", self.distribution, "--id", response["Invalidation"]["Id"])


def publish(aws, operation, release_id, dist, health):
    validate_release_id(release_id)
    prefix = f"releases/{release_id}"
    if operation == "deploy" and not aws.exists(f"{prefix}/release.json"):
        create(dist, release_id)
        verify(dist, release_id)
        aws.upload(dist, prefix)
    elif operation not in ("deploy", "rollback"):
        raise ValueError("Unknown operation")
    if not aws.exists(f"{prefix}/release.json"):
        raise RuntimeError("A completed target release does not exist")
    with tempfile.TemporaryDirectory(prefix="frame-release-") as temp:
        temp = Path(temp)
        target = temp / "target"
        # Re-download and hash the stored objects, including on rollback.
        aws.download_release(prefix, target)
        verify(target, release_id)
        previous = temp / "previous.html"
        if aws.exists("index.html"):
            aws.download_current(previous)
        activated = False
        try:
            # Mark the attempt before calling: a lost response can still mean
            # S3 accepted the new entry point.
            activated = True
            aws.activate(target / "index.html")
            aws.invalidate()
            health(release_id)
        except Exception as error:
            if activated and previous.exists():
                try:
                    aws.activate(previous)
                    aws.invalidate()
                    print("Restored the previous entry point after deployment failure.", flush=True)
                except Exception as recovery_error:
                    raise RuntimeError("Deployment AND automatic restoration failed; follow docs/operations.md immediately") from recovery_error
            elif activated:
                print("First deployment failed; no previous release exists to restore.", flush=True)
            raise error
    print(f"PASS {operation}: {release_id}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=["deploy", "rollback"])
    parser.add_argument("release")
    parser.add_argument("--dist", type=Path, default=Path("dist"))
    parser.add_argument("--browser-check", action="store_true")
    args = parser.parse_args()
    validate_release_id(args.release)
    bucket = os.environ["SITE_BUCKET"]
    distribution = os.environ["CLOUDFRONT_DISTRIBUTION_ID"]
    site_url = os.environ["SITE_URL"].rstrip("/")
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", bucket):
        raise ValueError("Invalid SITE_BUCKET")
    if not re.fullmatch(r"E[A-Z0-9]+", distribution):
        raise ValueError("Invalid CLOUDFRONT_DISTRIBUTION_ID")
    if not re.fullmatch(r"https://[a-zA-Z0-9.-]+", site_url):
        raise ValueError("SITE_URL must be a public HTTPS origin")

    def health(release):
        check_site(site_url, release)
        if args.browser_check:
            env = {**os.environ, "PLAYWRIGHT_BASE_URL": site_url, "EXPECTED_RELEASE": release}
            command = ["cmd.exe", "/d", "/c", "npm test"] if sys.platform == "win32" else ["npm", "test"]
            subprocess.run(command, check=True, env=env)

    publish(AwsCli(bucket, distribution), args.operation, args.release, args.dist, health)


if __name__ == "__main__":
    main()
