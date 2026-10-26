import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from smoke import check_site

SHA = 'a' * 40


class SmokeTests(unittest.TestCase):
    def html(self, release=SHA, script=None):
        script = script or f'/releases/{SHA}/app.js'
        return (f'<meta name="frame-release" content="{release}">'
                f'<script src="{script}"></script>'
                f'<link rel="stylesheet" href="/releases/{SHA}/style.css">').encode()

    def fetcher(self, html=None, wrong_asset=False, wrong_video=False):
        def fetch(url, byte_range=None):
            if url.endswith('/'):
                return 200, {'Content-Type': 'text/html'}, html if html is not None else self.html()
            if url.endswith('.js'):
                return 200, {'Content-Type': 'text/html' if wrong_asset else 'text/javascript'}, b'console.log(1)'
            if url.endswith('.css'):
                return 200, {'Content-Type': 'text/css'}, b'body {}'
            if url.endswith('.mp4'):
                return 206, {'Content-Type': 'video/mp4'}, b'not video' if wrong_video else b'\0\0\0\x18ftypmp42'
            raise AssertionError(url)
        return fetch

    def test_served_assets_and_video_are_checked(self):
        with patch('smoke.fetch', side_effect=self.fetcher()) as fetch:
            self.assertTrue(check_site('https://example.com', SHA))
            self.assertEqual(fetch.call_count, 4)

    def test_stale_html_is_not_a_successful_deployment(self):
        with patch('smoke.fetch', side_effect=self.fetcher(html=self.html('b' * 40))):
            with self.assertRaisesRegex(RuntimeError, 'Expected release'):
                check_site('https://example.com', SHA)

    def test_html_fallback_instead_of_javascript_fails(self):
        with patch('smoke.fetch', side_effect=self.fetcher(wrong_asset=True)):
            with self.assertRaisesRegex(RuntimeError, 'Invalid asset'):
                check_site('https://example.com', SHA)

    def test_external_asset_rejected(self):
        with patch('smoke.fetch', side_effect=self.fetcher(html=self.html(script=f'https://untrusted.example/releases/{SHA}/app.js'))):
            with self.assertRaisesRegex(RuntimeError, 'same-origin'):
                check_site('https://example.com', SHA)

    def test_non_mp4_body_rejected(self):
        with patch('smoke.fetch', side_effect=self.fetcher(wrong_video=True)):
            with self.assertRaisesRegex(RuntimeError, 'not playable'):
                check_site('https://example.com', SHA)


if __name__ == '__main__':
    unittest.main()
