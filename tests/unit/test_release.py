import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from release_manifest import create, verify, validate_release_id
from release import publish
from smoke import Document

SHA = 'a' * 40


class FakeAws:
    def __init__(self, root):
        self.root = root
        self.events = []

    def exists(self, key):
        return (self.root / key).is_file()

    def upload(self, directory, prefix):
        self.events.append('upload')
        shutil.copytree(directory, self.root / prefix, dirs_exist_ok=True)

    def download_release(self, prefix, directory):
        self.events.append('verify-storage')
        shutil.copytree(self.root / prefix, directory)

    def download_current(self, path):
        shutil.copyfile(self.root / 'index.html', path)

    def activate(self, path):
        self.events.append('activate')
        shutil.copyfile(path, self.root / 'index.html')

    def invalidate(self):
        self.events.append('invalidate')


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dist = self.root / 'dist'
        self.dist.mkdir()
        self.html = f'<meta name="frame-release" content="{SHA}"><script src="/releases/{SHA}/assets/app.js"></script>'
        (self.dist / 'index.html').write_text(self.html)
        (self.dist / 'assets').mkdir()
        (self.dist / 'assets/app.js').write_text('console.log("app")')
        self.remote = self.root / 'remote'
        self.remote.mkdir()
        self.aws = FakeAws(self.remote)

    def test_publish_verifies_objects_before_switching_entry_point(self):
        def health(sha):
            self.assertEqual(sha, SHA)
            self.assertEqual((self.remote / 'index.html').read_text(), self.html)
            self.aws.events.append('health')
        publish(self.aws, 'deploy', SHA, self.dist, health)
        self.assertEqual(self.aws.events, ['upload', 'verify-storage', 'activate', 'invalidate', 'health'])

    def test_health_failure_restores_previous_entry_point_and_still_fails(self):
        (self.remote / 'index.html').write_text('previous working release')
        def fail(sha):
            raise RuntimeError('unhealthy deployment')
        with self.assertRaisesRegex(RuntimeError, 'unhealthy deployment'):
            publish(self.aws, 'deploy', SHA, self.dist, fail)
        self.assertEqual((self.remote / 'index.html').read_text(), 'previous working release')
        self.assertEqual(self.aws.events[-2:], ['activate', 'invalidate'])

    def test_rollback_uses_stored_release_and_does_not_rebuild_or_upload(self):
        create(self.dist, SHA)
        shutil.copytree(self.dist, self.remote / f'releases/{SHA}')
        (self.remote / 'index.html').write_text('newer release')
        publish(self.aws, 'rollback', SHA, Path('/missing-dist'), lambda sha: None)
        self.assertNotIn('upload', self.aws.events)
        self.assertEqual((self.remote / 'index.html').read_text(), self.html)

    def test_corrupt_asset_prevents_activation(self):
        create(self.dist, SHA)
        shutil.copytree(self.dist, self.remote / f'releases/{SHA}')
        (self.remote / f'releases/{SHA}/assets/app.js').write_text('corrupted')
        with self.assertRaisesRegex(ValueError, 'integrity failure'):
            publish(self.aws, 'rollback', SHA, self.dist, lambda sha: None)
        self.assertNotIn('activate', self.aws.events)

    def test_missing_release_prevents_rollback(self):
        with self.assertRaisesRegex(RuntimeError, 'does not exist'):
            publish(self.aws, 'rollback', SHA, self.dist, lambda sha: None)
        self.assertNotIn('activate', self.aws.events)

    def test_invalidation_failure_also_restores_previous_entry_point(self):
        (self.remote / 'index.html').write_text('previous working release')
        calls = []
        def invalidate():
            calls.append(1)
            if len(calls) == 1:
                raise RuntimeError('invalidation failed')
        self.aws.invalidate = invalidate
        with self.assertRaisesRegex(RuntimeError, 'invalidation failed'):
            publish(self.aws, 'deploy', SHA, self.dist, lambda sha: None)
        self.assertEqual((self.remote / 'index.html').read_text(), 'previous working release')
        self.assertEqual(len(calls), 2)

    def test_rerun_reuses_completed_release(self):
        publish(self.aws, 'deploy', SHA, self.dist, lambda sha: None)
        self.aws.events.clear()
        publish(self.aws, 'deploy', SHA, self.dist, lambda sha: None)
        self.assertNotIn('upload', self.aws.events)

    def test_manifest_rejects_path_traversal(self):
        create(self.dist, SHA)
        manifest = json.loads((self.dist / 'release.json').read_text())
        manifest['files']['../../outside'] = 'anything'
        (self.dist / 'release.json').write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, 'escapes'):
            verify(self.dist, SHA)

    def test_release_ids_reject_paths_and_shell_input(self):
        for value in ['main', '../escape', 'a' * 39, '; echo hello', 'A' * 40]:
            with self.assertRaises(ValueError):
                validate_release_id(value)

    def test_document_extracts_real_release_assets(self):
        doc = Document()
        doc.feed(self.html + '<link rel="stylesheet" href="/releases/a/style.css">')
        self.assertEqual(doc.release, SHA)
        self.assertEqual(len(doc.assets), 2)


if __name__ == '__main__':
    unittest.main()
