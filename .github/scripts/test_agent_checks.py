"""Exercise leak rejection and non-destructive Terraform maintenance boundaries."""
import importlib.util
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
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

    def test_progress_never_echoes_commands_or_output_and_redacts_messages(self):
        run = load('run_agent')
        secret = 'fixture-private-credential-123'
        event = {'type': 'item.completed', 'item': {'type': 'command_execution',
            'command': 'sshpass -p ' + secret + ' ssh guest',
            'aggregated_output': secret, 'exit_code': 1}}
        self.assertEqual(run.progress_event(event), 'Inspecting a VM or LXC over SSH — exit 1')
        self.assertNotIn(secret, run.progress_event(event))
        self.assertNotIn(secret, run.progress_event({'type': 'error', 'message': secret}))
        message = run.progress_event({'type': 'item.completed', 'item': {'type': 'agent_message',
            'text': 'Upgrading Trivy with ' + secret + ' and hvs.' + 'A' * 24 + ' password=hunter22x'}},
            {secret})
        self.assertTrue(message.startswith('Agent: Upgrading Trivy'))
        for leaked in [secret, 'hvs.AAAA', 'hunter22x']:
            self.assertNotIn(leaked, message)
        plan = run.progress_event({'type': 'item.updated', 'item': {'type': 'todo_list',
            'items': [{'text': 'Check k3s', 'completed': True}, {'text': 'Audit hosts', 'completed': False}]}})
        self.assertEqual(plan, 'Plan: [x] Check k3s; [ ] Audit hosts')

    def test_live_progress_streams_without_exposing_tool_output(self):
        run = load('run_agent')
        secret = 'fixture-private-credential-123'
        event = {'type': 'item.completed', 'item': {'type': 'command_execution',
            'command': 'kubectl get pods', 'aggregated_output': secret, 'exit_code': 0}}
        code = 'import sys,time; sys.stdin.read(); time.sleep(.1); print(' + repr(json.dumps(event)) + ', flush=True)'
        with tempfile.TemporaryDirectory() as folder:
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                result = run.execute_codex([sys.executable, '-c', code], 'fixture instructions',
                                          dict(os.environ), Path(folder), timeout=5, heartbeat=.03)
            self.assertEqual(result, 0)
            self.assertIn('Still running', output.getvalue())
            self.assertIn('Inspecting Kubernetes resources — exit 0', output.getvalue())
            self.assertNotIn(secret, output.getvalue())
            self.assertNotIn(secret, Path(folder, 'progress.log').read_text())
            self.assertIn(secret, Path(folder, 'codex.log').read_text())

    def test_launcher_does_not_preload_vault_and_requires_completion(self):
        run = load('run_agent')
        for completed in [False, True, 'ATTENTION']:
            with tempfile.TemporaryDirectory() as folder:
                def execute(args, instructions, env, directory):
                    self.assertNotIn('CLOUDFLARE_API_TOKEN', env)
                    self.assertIn('direct access', instructions)
                    Path(folder, 'result.md').write_text('Verified assessment.')
                    if completed:
                        Path(folder, 'SUCCESS').write_text('ATTENTION\n' if completed == 'ATTENTION' else 'SUCCESS')
                    return 0
                with patch.dict(os.environ, {'PATH': os.environ['PATH']}, clear=True), \
                     patch('sys.argv', ['run_agent.py', 'update', folder]), \
                     patch.object(run, 'execute_codex', side_effect=execute), \
                     patch('check_credentials.secret_values', return_value=set()):
                    self.assertEqual(run.main(), 0 if completed else 1)
                self.assertIn('Verified assessment.', Path(folder, 'summary.md').read_text())


if __name__ == '__main__':
    unittest.main()
