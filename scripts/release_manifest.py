"""Checksummed, completed release manifests. No AWS dependencies."""
import hashlib
import json
import re
from pathlib import Path


def validate_release_id(value):
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ValueError("Release ID must be a full lowercase Git commit SHA")
    return value


def create(directory, release_id):
    validate_release_id(release_id)
    directory = Path(directory)
    html = (directory / "index.html").read_text()
    if f'content="{release_id}"' not in html or f"/releases/{release_id}/" not in html:
        raise ValueError("Build with RELEASE_ID=<SHA> and ASSET_BASE=/releases/<SHA>/ first")
    files = {
        str(path.relative_to(directory)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(directory.rglob("*"))
        if path.is_file() and path.name != "release.json"
    }
    manifest = {"release_id": release_id, "files": files}
    (directory / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def verify(directory, release_id):
    validate_release_id(release_id)
    directory = Path(directory).resolve()
    manifest = json.loads((directory / "release.json").read_text())
    if manifest.get("release_id") != release_id or "index.html" not in manifest.get("files", {}):
        raise ValueError("Release identity or entry point is invalid")
    for filename, expected in manifest["files"].items():
        path = (directory / filename).resolve()
        if directory not in path.parents:
            raise ValueError("Manifest path escapes release directory")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f"Release integrity failure: {filename}")
    return manifest
