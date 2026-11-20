import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import yaml

spec = importlib.util.spec_from_file_location('infra_agent', Path(__file__).with_name('infra_agent.py'))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


class ProposalValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.patch = mock.patch.object(agent, 'ROOT', self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.context = {'upstream_releases': {'vault': {'tag_name': 'v2.3.0'}},
                        'chart_releases': {'repo': {'charts': {'example': [{'version': '1.3.0'}]}}},
                        'traffic': [{'ClientHost': '93.184.215.14'}]}

    def put(self, path, content):
        full = self.root / path
        full.parent.mkdir(parents=True, exist_ok=True)
        full.write_text(content)
        return full

    def validate(self, kind, path, content):
        return agent.validate_change(kind, path, content, self.context)

    def test_allows_verified_forward_source_pin(self):
        path = 'ansible/03-vault/vault-lxc/roles/vault/defaults/main.yml'
        self.put(path, 'vault_version: "2.2.0"\nport: 8200\n')
        self.validate('update', path, 'vault_version: "2.3.0"\nport: 8200\n')

    def test_rejects_unverified_source_pin(self):
        path = 'ansible/03-vault/vault-lxc/roles/vault/defaults/main.yml'
        self.put(path, 'vault_version: "2.2.0"\n')
        with self.assertRaises(ValueError):
            self.validate('update', path, 'vault_version: "2.4.0"\n')

    def test_rejects_source_configuration_change(self):
        path = 'ansible/03-vault/vault-lxc/roles/vault/defaults/main.yml'
        self.put(path, 'vault_version: "2.2.0"\nport: 8200\n')
        with self.assertRaises(ValueError):
            self.validate('update', path, 'vault_version: "2.3.0"\nport: 1234\n')

    def test_rejects_major_upgrade_and_downgrade(self):
        for value in ['3.0.0', '2.1.0']:
            with self.assertRaises(ValueError):
                agent.version_change('2.2.0', value)

    def test_rejects_terraform_and_traversal(self):
        for kind in ['update', 'security']:
            for path in ['terraform/cloudflare/zones/blocked-ips.txt', '../outside', '/tmp/outside']:
                with self.assertRaises(ValueError):
                    self.validate(kind, path, 'content')

    def test_allows_evidenced_public_ban(self):
        path = agent.CROWDSEC + 'blocked-ips.txt'
        self.put(path, '# prior\n1.1.1.1\n')
        self.validate('security', path, '# prior\n1.1.1.1\n# repeated scanning\n93.184.215.14\n')

    def test_rejects_private_unseen_or_removed_bans(self):
        path = agent.CROWDSEC + 'blocked-ips.txt'
        self.put(path, '1.1.1.1\n')
        for text in ['1.1.1.1\n192.168.1.2\n', '1.1.1.1\n8.8.8.8\n', '93.184.215.14\n']:
            with self.assertRaises(ValueError):
                self.validate('security', path, text)

    def test_no_numeric_cap_on_evidenced_bans(self):
        path = agent.CROWDSEC + 'blocked-ips.txt'
        self.put(path, '')
        addresses = [f'93.184.215.{i}' for i in range(1, 31)]
        self.context['traffic'] = [{'ClientHost': ip} for ip in addresses]
        self.validate('security', path, '\n'.join(addresses) + '\n')

    def test_protects_rbac_parsers_and_validator(self):
        for suffix in ['agent-rbac.yaml', 'parsers/trusted-clients.yaml', 'check.py', 'externalsecret.yaml']:
            with self.assertRaises(ValueError):
                self.validate('security', agent.CROWDSEC + suffix, '{}')

    def test_preserves_existing_rule_names(self):
        path = agent.CROWDSEC + 'scenarios/probe.yaml'
        self.put(path, 'name: custom/probe\nfilter: old\n')
        self.validate('security', path, 'name: custom/probe\nfilter: improved\n')
        with self.assertRaises(ValueError):
            self.validate('security', path, 'name: custom/replacement\n')

    def test_only_appends_configmap_files(self):
        path = agent.CROWDSEC + 'kustomization.yaml'
        old = {'resources': ['namespace.yaml'], 'configMapGenerator': [{'name': 'rules', 'files': ['old.yaml']}]}
        self.put(path, yaml.safe_dump(old))
        new = json.loads(json.dumps(old)); new['configMapGenerator'][0]['files'].append('new.yaml')
        self.validate('security', path, yaml.safe_dump(new))
        new['resources'].append('rbac.yaml')
        with self.assertRaises(ValueError):
            self.validate('security', path, yaml.safe_dump(new))

    def test_rejects_symlink(self):
        path = agent.CROWDSEC + 'blocked-ips.txt'
        target = self.put('elsewhere', '')
        full = self.root / path; full.parent.mkdir(parents=True)
        full.symlink_to(target)
        with self.assertRaises(ValueError):
            self.validate('security', path, '')

    def test_helm_updates_are_version_only(self):
        path = agent.INFRA + 'example/helmrelease.yaml'
        old = {'spec': {'chart': {'spec': {'chart': 'example', 'version': '1.2.x'}}, 'values': {'replicas': 2}}}
        self.put(path, yaml.safe_dump(old))
        new = json.loads(json.dumps(old)); new['spec']['chart']['spec']['version'] = '1.3.x'
        self.validate('update', path, yaml.safe_dump(new))
        new['spec']['values']['replicas'] = 3
        with self.assertRaises(ValueError):
            self.validate('update', path, yaml.safe_dump(new))

    def test_codex_receives_no_host_github_or_vault_credentials(self):
        directory = self.root / 'agent'; directory.mkdir()
        self.put('.github/agent-prompts/ai-update-agent.md', 'Return a proposal')
        (directory / 'context.json').write_text('{}')
        with mock.patch.dict(agent.os.environ, {'DEEPSEEK_APIKEY': 'model-test', 'HOST_PASSWORD': 'host-test',
                             'GH_TOKEN': 'github-test', 'VAULT_PASSWORD': 'vault-test'}), \
             mock.patch.object(agent.subprocess, 'run', return_value=mock.Mock(returncode=0)) as run:
            agent.propose('update', directory)
        env = run.call_args.kwargs['env']
        self.assertNotIn('HOST_PASSWORD', env)
        self.assertNotIn('GH_TOKEN', env)
        self.assertNotIn('VAULT_PASSWORD', env)
        self.assertEqual(env['DEEPSEEK_APIKEY'], 'model-test')
        self.assertIn('read-only', run.call_args.args[0])


if __name__ == '__main__':
    unittest.main()
