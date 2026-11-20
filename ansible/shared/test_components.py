"""Test bootstrap environment selection without contacting infrastructure."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class BootstrapExecutionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bootstrap = self.root / 'ansible'
        (self.bootstrap / 'shared').mkdir(parents=True)
        self.part = self.bootstrap / '00-bootstrap' / '01-example'
        self.part.mkdir(parents=True)
        shutil.copy(Path(__file__).with_name('run-component.sh'), self.bootstrap / 'shared/run-component.sh')
        (self.part / 'playbook.yml').write_text('---\n[]\n')
        (self.part / '.env').write_text(
            'TARGET_HOST=192.0.2.10\nTARGET_USER=root\nTARGET_PASSWORD=""\nCOMPONENT_VALUE=selected\n'
        )
        (self.root / '.env').write_text('ROOT_ENV_LOADED=yes\n')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        fake = self.bin / 'ansible-playbook'
        fake.write_text(
            '#!/usr/bin/env python3\nimport json,os,sys\n'
            'print(json.dumps({"args":sys.argv[1:],'
            '"value":os.getenv("COMPONENT_VALUE"),'
            '"root":os.getenv("ROOT_ENV_LOADED"),'
            '"password":os.getenv("TARGET_PASSWORD")}))\n'
        )
        fake.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        COMPONENT_VALUE='inherited')
        self.env.pop('ROOT_ENV_LOADED', None)

    def run_part(self, part=None, *args):
        return subprocess.run(
            ['bash', str(self.bootstrap / 'shared/run-component.sh'), str(part or self.part), *args],
            env=self.env, text=True, capture_output=True, cwd=self.root,
        )

    def test_component_values_override_parent_without_loading_root_env(self):
        result = self.run_part()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data['value'], 'selected')
        self.assertIsNone(data['root'])
        self.assertEqual(data['password'], '')

    def test_ansible_arguments_and_target_are_forwarded(self):
        result = self.run_part(None, '--syntax-check', '--ask-pass')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['args'], [
            '-i', '192.0.2.10,', '-u', 'root', str(self.part / 'playbook.yml'),
            '--syntax-check', '--ask-pass',
        ])

    def test_missing_component_environment_fails_before_execution(self):
        (self.part / '.env').unlink()
        result = self.run_part()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('.env.example', result.stderr)
        self.assertEqual(result.stdout, '')

    def test_directory_outside_bootstrap_is_rejected(self):
        result = self.run_part(self.root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('numbered stage component', result.stderr)
        self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
