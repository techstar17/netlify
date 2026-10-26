"""Verify the actual HTML, JS, CSS, and media served by a release."""
import argparse
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen


class Document(HTMLParser):
    def __init__(self):
        super().__init__()
        self.release = None
        self.assets = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "meta" and attrs.get("name") == "frame-release":
            self.release = attrs.get("content")
        if tag == "script" and attrs.get("src"):
            self.assets.append(attrs["src"])
        if tag == "link" and attrs.get("rel") == "stylesheet":
            self.assets.append(attrs["href"])


def fetch(url, byte_range=None):
    headers = {"User-Agent": "FRAME-release-smoke/1.0"}
    if byte_range:
        headers["Range"] = byte_range
    with urlopen(Request(url, headers=headers), timeout=30) as response:
        return response.status, response.headers, response.read(10 * 1024 * 1024)


def check_site(base_url, release_id):
    base_url = base_url.rstrip("/") + "/"
    status, headers, body = fetch(base_url)
    if status != 200 or "text/html" not in headers.get("Content-Type", ""):
        raise RuntimeError("The public entry point is not an HTML document")
    doc = Document()
    doc.feed(body.decode())
    if doc.release != release_id:
        raise RuntimeError(f"Expected release {release_id}, received {doc.release}")
    if not any(asset.endswith(".js") for asset in doc.assets) or not any(asset.endswith(".css") for asset in doc.assets):
        raise RuntimeError("Missing production JS/CSS references")
    for asset in doc.assets:
        url = urljoin(base_url, asset)
        if urlsplit(url).netloc != urlsplit(base_url).netloc or f"/releases/{release_id}/" not in url:
            raise RuntimeError("Assets must belong to the immutable same-origin release")
        status, asset_headers, asset_body = fetch(url)
        content_type = asset_headers.get("Content-Type", "").lower()
        expected_type = "javascript" if asset.endswith(".js") else "text/css"
        if status != 200 or not asset_body or expected_type not in content_type:
            raise RuntimeError(f"Invalid asset response: {asset}")
    url = urljoin(base_url, f"releases/{release_id}/video/sample.mp4")
    status, headers, body = fetch(url, "bytes=0-1023")
    if status not in (200, 206) or "video/mp4" not in headers.get("Content-Type", "") or b"ftyp" not in body[:32]:
        raise RuntimeError("Sample video is not playable MP4 content")
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("release")
    args = parser.parse_args()
    check_site(args.url, args.release)
    print("PASS public HTML release identity, JS, CSS, and MP4")
