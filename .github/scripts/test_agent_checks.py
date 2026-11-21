"""Exercise leak rejection and non-destructive Terraform maintenance boundaries."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Checks(unittest.TestCase):
    def test_terraform_rejects_destroy_replacement_and_errored_plan(self):
        guard = load('terraform_apply')
        for actions in [['delete'], ['delete', 'create'], ['create', 'delete']]:
            with self.assertRaises(ValueError):
                guard.validate({'resource_changes': [{'change': {'actions': actions}}]})
        with self.assertRaises(ValueError):
            guard.validate({'errored': True})
        guard.validate({'resource_changes': [{'change': {'actions': ['update']}}]})
        guard.validate({'resource_changes': []})

    def test_staged_credentials_rejected_and_clean_source_accepted(self):
        with tempfile.TemporaryDirectory() as folder:
            def git(*args):
                return subprocess.check_output(['git', '-C', folder, *args], stderr=subprocess.DEVNULL)
            git('init')
            path = Path(folder) / 'source.txt'
            env = {**os.environ, 'TEST_PASSWORD': 'fixture-private-credential-123',
                   'VAULT_ADDR': '', 'VAULT_USERNAME': ''}
            for content, expected in [('safe source\n', 0), ('fixture-private-credential-123', 1),
                                      ('-----BEGIN ' + 'PRIVATE KEY-----\nfixture\n', 1)]:
                path.write_text(content)
                git('add', 'source.txt')
                result = subprocess.run(['python3', str(HERE / 'check_credentials.py')],
                                        cwd=folder, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, expected)
                self.assertNotIn(env['TEST_PASSWORD'], result.stdout + result.stderr)
            path.write_text('safe source')
            git('add', 'source.txt')
            (Path(folder) / '.env').write_text('SAFE=fixture')
            git('add', '.env')
            result = subprocess.run(['python3', str(HERE / 'check_credentials.py')],
                                    cwd=folder, env=env, capture_output=True)
            self.assertEqual(result.returncode, 1)

    def test_report_redacts_multiline_credentials_and_private_keys(self):
        run = load('run_agent')
        value = 'private\nfixture-password'
        result = run.redact(value + json.dumps(value)[1:-1] +
                            '-----BEGIN RSA ' + 'PRIVATE KEY-----\nfixture\n-----END RSA ' + 'PRIVATE KEY-----', {value})
        self.assertNotIn('fixture', result)

    def test_launcher_does_not_preload_vault_and_requires_completion(self):
        run = load('run_agent')
        for completed in [False, True]:
            with tempfile.TemporaryDirectory() as folder:
                def execute(args, **kwargs):
                    self.assertNotIn('CLOUDFLARE_API_TOKEN', kwargs['env'])
                    self.assertIn('direct access', kwargs['input'])
                    Path(folder, 'result.md').write_text('Verified assessment.')
                    if completed:
                        Path(folder, 'SUCCESS').write_text('SUCCESS')
                    return subprocess.CompletedProcess(args, 0)
                with patch.dict(os.environ, {'PATH': os.environ['PATH']}, clear=True), \
                     patch('sys.argv', ['run_agent.py', 'update', folder]), \
                     patch.object(run.subprocess, 'run', side_effect=execute), \
                     patch('check_credentials.secret_values', return_value=set()):
                    self.assertEqual(run.main(), 0 if completed else 1)
                self.assertIn('Verified assessment.', Path(folder, 'summary.md').read_text())


if __name__ == '__main__':
    unittest.main()
