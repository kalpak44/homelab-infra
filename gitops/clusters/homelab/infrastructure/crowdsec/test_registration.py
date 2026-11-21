"""Regression checks for restarting pods with retained or lost LAPI credentials."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml


class Registration(unittest.TestCase):
    def run_init(self, saved=False, valid=False, reject=False):
        hr = yaml.safe_load(Path(__file__).with_name('helmrelease.yaml').read_text())
        patch = yaml.safe_load(hr['spec']['postRenderers'][0]['kustomize']['patches'][0]['patch'])
        script = patch[0]['value'][2]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ['bin', 'staging', 'config', 'etc']:
                (root / name).mkdir()
            script = script.replace('/staging/etc/crowdsec', str(root / 'staging'))
            script = script.replace('/etc/crowdsec', str(root / 'etc/crowdsec'))
            script = script.replace('/tmp_config', str(root / 'config'))
            script = script.replace('/proc/sys/kernel/random/uuid', str(root / 'uuid'))
            (root / 'uuid').write_text('unique-incarnation')
            credentials = root / 'config/local_api_credentials.yaml'
            if saved:
                credentials.write_text('retained-credential')
            (root / 'bin/nc').write_text('#!/bin/sh\nexit 0\n')
            (root / 'bin/cscli').write_text('''#!/bin/sh
if [ "$2" = status ]; then [ "$VALID" = 1 ]; exit; fi
[ "$2" = register ] || exit 2
[ "$REJECT" = 0 ] || exit 3
while [ "$#" -gt 0 ]; do
  case "$1" in --machine) shift; printf '%s' "$1" > "$MACHINE_FILE";; -f) shift; file="$1";; esac
  shift
done
printf '%s' 'new-credential' > "$file"
''')
            for binary in (root / 'bin').iterdir():
                binary.chmod(0o700)
            env = {**os.environ, 'PATH': str(root / 'bin') + ':' + os.environ['PATH'],
                   'VALID': str(int(valid)), 'REJECT': str(int(reject)),
                   'MACHINE_FILE': str(root / 'machine'), 'USERNAME': 'existing-pod',
                   'LAPI_HOST': 'example.test', 'LAPI_PORT': '8080',
                   'LAPI_URL': 'http://example.test:8080', 'REGISTRATION_TOKEN': 'fixture'}
            result = subprocess.run(['sh', '-c', script], env=env, capture_output=True, text=True)
            return result.returncode, credentials.read_text() if credentials.exists() else None, (
                (root / 'machine').read_text() if (root / 'machine').exists() else None)

    def test_node_reboot_reuses_valid_credentials(self):
        self.assertEqual(self.run_init(saved=True, valid=True), (0, 'retained-credential', None))

    def test_lost_credentials_use_unique_identity(self):
        self.assertEqual(self.run_init(), (0, 'new-credential', 'existing-pod-unique-incarnation'))

    def test_stale_credentials_can_recover_without_deleting_machine(self):
        self.assertEqual(self.run_init(saved=True), (0, 'new-credential', 'existing-pod-unique-incarnation'))

    def test_rejected_registration_preserves_prior_credentials(self):
        code, credentials, machine = self.run_init(saved=True, reject=True)
        self.assertNotEqual(code, 0)
        self.assertEqual(credentials, 'retained-credential')
        self.assertIsNone(machine)


if __name__ == '__main__':
    unittest.main()
