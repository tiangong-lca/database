#!/usr/bin/env python3
"""Verify local Auth defaults and preserved explicit hosted profiles without hosted access."""
from __future__ import annotations
import copy
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import tomllib
import unittest
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
MAIN_REF = 'qgzvkongdjqiiamzbbts'
DEV_REF = 'submidrhbtknjxfympna'
CUSTOM_REF = 'abcdefghijklmnopqrst'
REQUIRE_CLI = '--require-cli' in sys.argv
if REQUIRE_CLI:
    sys.argv.remove('--require-cli')
CLI = os.environ.get('SUPABASE_CLI') or shutil.which('supabase')


def merge(base, overlay):
    result = copy.deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


class AuthProfiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = tomllib.loads((ROOT / 'supabase/config.toml').read_text())
        cls.baseline = json.loads((ROOT / 'scripts/fixtures/auth-profile-baseline.json').read_text())

    def test_base_auth_is_loopback_only(self):
        auth = self.config['auth']
        self.assertEqual(auth['site_url'], 'http://localhost:8000')
        self.assertEqual(set(auth['additional_redirect_urls']),
                         {'http://localhost:8000/*', 'http://127.0.0.1:8000/*'})
        for url in [auth['site_url'], *auth['additional_redirect_urls']]:
            self.assertIn(urlsplit(url).hostname, {'localhost', '127.0.0.1', '::1'})

    def test_explicit_main_preserves_entire_prior_auth_and_seed(self):
        remote = self.config['remotes']['main']
        self.assertEqual(remote['project_id'], MAIN_REF)
        self.assertEqual(merge(self.config['auth'], remote['auth']), self.baseline['main_auth'])
        # CLI remote merging otherwise disables seeds when a remote omits this field.
        self.assertEqual(remote['db']['seed'], self.baseline['seed'])

    def test_explicit_dev_preserves_entire_prior_auth_and_binding(self):
        remote = self.config['remotes']['dev']
        self.assertEqual(remote['project_id'], DEV_REF)
        self.assertEqual(merge(self.config['auth'], remote['auth']), self.baseline['dev_auth'])
        self.assertEqual(remote['db']['seed'], {'enabled': True, 'sql_paths': ['./seeds/dev.sql']})

    def test_remote_bindings_are_unique(self):
        refs = [remote['project_id'] for remote in self.config['remotes'].values()]
        self.assertEqual(len(refs), len(set(refs)))
        self.assertEqual(set(refs), {MAIN_REF, DEV_REF})

    def test_pinned_cli_selects_base_main_and_dev_against_loopback_api(self):
        if not CLI:
            if REQUIRE_CLI:
                self.fail('Pinned Supabase CLI is required for profile qualification')
            self.skipTest('set SUPABASE_CLI or pass --require-cli with CLI on PATH')
        with tempfile.TemporaryDirectory(prefix='auth-profile-contract-') as temporary:
            root = Path(temporary)
            (root / 'supabase').mkdir()
            shutil.copy2(ROOT / 'supabase/config.toml', root / 'supabase/config.toml')
            shutil.copytree(ROOT / 'supabase/templates', root / 'supabase/templates')
            requests = []
            class Handler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    requests.append(('GET', self.path))
                    data = json.dumps({'auth': {'site_url': 'https://fixture.invalid'}}).encode()
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                def do_POST(self):
                    requests.append(('POST', self.path))
                    self.send_error(405)
                def log_message(self, *args):
                    pass
            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                profile = root / 'profile.json'
                profile.write_text(json.dumps({
                    'name': 'offline-auth-contract',
                    'api_url': f'http://127.0.0.1:{server.server_port}',
                    'dashboard_url': 'http://127.0.0.1', 'project_host': 'localhost',
                }))
                env = {key: os.environ[key] for key in ('PATH', 'TMPDIR', 'SYSTEMROOT') if key in os.environ}
                env.update({'HOME': str(root), 'USERPROFILE': str(root), 'SUPABASE_HOME': str(root / '.supabase'),
                            'SUPABASE_ACCESS_TOKEN': 'sbp_' + 'a' * 40, 'NO_COLOR': '1'})
                prefix = [CLI] if not CLI.endswith('.js') else ['node', CLI]
                version = subprocess.run(prefix + ['--version'], env=env, capture_output=True,
                                         text=True, timeout=30, check=True)
                self.assertEqual(version.stdout.strip(), '2.117.0')
                for ref, site, redirects in [
                    (CUSTOM_REF, 'http://localhost:8000', self.config['auth']['additional_redirect_urls']),
                    (MAIN_REF, self.baseline['main_auth']['site_url'], self.baseline['main_auth']['additional_redirect_urls']),
                    (DEV_REF, self.baseline['dev_auth']['site_url'], self.baseline['dev_auth']['additional_redirect_urls']),
                ]:
                    with self.subTest(ref=ref):
                        before = len(requests)
                        run = subprocess.run(prefix + ['config', 'diff', '--project-ref', ref,
                            '--workdir', str(root), '--profile', str(profile), '--output-format', 'json'],
                            env=env, capture_output=True, text=True, timeout=40)
                        self.assertEqual(run.returncode, 0, run.stderr)
                        result = json.loads(run.stdout)
                        values = {tuple(change['path']): change['local'] for change in result['changes']}
                        self.assertEqual(values[('auth', 'site_url')], site)
                        self.assertEqual(values[('auth', 'additional_redirect_urls')], redirects)
                        self.assertIn(('GET', f'/v2/projects/{ref}/config'), requests[before:])
                self.assertTrue(all(method == 'GET' for method, _ in requests))
                self.assertEqual((root / 'supabase/config.toml').read_bytes(),
                                 (ROOT / 'supabase/config.toml').read_bytes())
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)


if __name__ == '__main__':
    unittest.main()
