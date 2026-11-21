import importlib.util
import json
import sys
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import yaml

spec = importlib.util.spec_from_file_location('infra_agent', Path(__file__).with_name('infra_agent.py'))
agent = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = agent
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

    def test_allows_required_source_schema_migration(self):
        path = 'ansible/03-vault/vault-lxc/roles/vault/defaults/main.yml'
        self.put(path, 'vault_version: "2.2.0"\nport: 8200\n')
        self.validate('update', path, 'vault_version: "2.3.0"\nport: 1234\n')

    def test_allows_major_upgrade_but_rejects_downgrade(self):
        agent.version_change('2.2.0', '3.0.0')
        with self.assertRaises(ValueError):
            agent.version_change('2.2.0', '2.1.0')

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

    def test_helm_migrations_preserve_identity(self):
        path = agent.INFRA + 'example/helmrelease.yaml'
        old = {'spec': {'chart': {'spec': {'chart': 'example', 'version': '1.2.x'}}, 'values': {'replicas': 2}}}
        self.put(path, yaml.safe_dump(old))
        new = json.loads(json.dumps(old)); new['spec']['chart']['spec']['version'] = '1.3.x'
        self.validate('update', path, yaml.safe_dump(new))
        new['spec']['values']['replicas'] = 3
        self.validate('update', path, yaml.safe_dump(new))
        new['metadata'] = {'name': 'different-identity'}
        with self.assertRaises(ValueError):
            self.validate('update', path, yaml.safe_dump(new))

    def test_codex_receives_no_host_github_or_vault_credentials(self):
        directory = self.root / 'agent'; directory.mkdir()
        self.put('.github/agent-prompts/ai-update-agent.md', 'Return a proposal')
        (directory / 'context.json').write_text('{}')
        with mock.patch.dict(agent.os.environ, {'DEEPSEEK_APIKEY': 'model-test', 'HOST_PASSWORD': 'host-test',
                             'GH_TOKEN': 'github-test', 'VAULT_PASSWORD': 'vault-test'}), \
             mock.patch.object(agent.migrations, 'operator_environment', return_value={'DEEPSEEK_APIKEY':'model-test'}), \
             mock.patch.object(agent.subprocess, 'run', return_value=mock.Mock(returncode=0)) as run:
            agent.propose('update', directory)
        env = run.call_args.kwargs['env']
        self.assertNotIn('HOST_PASSWORD', env)
        self.assertNotIn('GH_TOKEN', env)
        self.assertNotIn('VAULT_PASSWORD', env)
        self.assertEqual(env['DEEPSEEK_APIKEY'], 'model-test')
        self.assertIn('read-only', run.call_args.args[0])




class AutonomousLoopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.context = {'http_health': {'https://service.test/': 200}, 'history': [], 'research': {}}
        (self.directory / 'context.json').write_text(json.dumps(self.context))

    def proposal(self, complete=False, research=None):
        return {'report': 'Verified migration assessment', 'complete': complete,
                'research_urls': research or [], 'plan': {'target': 'vault'},
                'changes': [], 'operations': [] if complete or research else
                [{'type': 'configure', 'target': 'vault-lxc', 'layer': ''}]}

    def test_research_execution_and_refreshed_verification_without_review(self):
        proposals = [self.proposal(research=['https://developer.hashicorp.com/vault/docs']),
                     self.proposal(), self.proposal(complete=True)]
        def propose(*args):
            (self.directory / 'proposal.json').write_text(json.dumps(proposals.pop(0)))
        def apply(*args):
            (self.directory / 'summary.md').write_text('Migration executed and checks passed')
        with mock.patch.object(agent, 'collect'), mock.patch.object(agent, 'propose', side_effect=propose), \
             mock.patch.object(agent, 'apply', side_effect=apply) as execute, \
             mock.patch.object(agent.migrations, 'research', return_value={'https://developer.hashicorp.com/vault/docs':'Migration reference'}):
            agent.run('update', self.directory)
        execute.assert_called_once()
        self.assertIn('refreshed health/version verification', (self.directory / 'summary.md').read_text())

    def test_failed_stage_returns_diagnostics_to_repair_loop(self):
        proposals = [self.proposal(), self.proposal(), self.proposal(complete=True)]
        diagnostics=[]
        def propose(*args):
            diagnostics.append(json.loads((self.directory / 'context.json').read_text()))
            (self.directory / 'proposal.json').write_text(json.dumps(proposals.pop(0)))
        calls=[]
        def apply(*args):
            calls.append(True)
            if len(calls)==1:
                raise agent.CommandFailure('Migration needs a schema repair', mock.Mock(stdout='old schema unsupported',stderr=''))
            (self.directory / 'summary.md').write_text('Repair succeeded')
        with mock.patch.object(agent, 'collect'), mock.patch.object(agent, 'propose', side_effect=propose), \
             mock.patch.object(agent, 'apply', side_effect=apply):
            agent.run('update', self.directory)
        self.assertEqual(len(calls), 2)
        self.assertIn('old schema unsupported', diagnostics[1]['history'][-1]['diagnostic'])

    def test_completion_after_failed_stage_is_rejected(self):
        proposals = [self.proposal(), self.proposal(complete=True)]
        def propose(*args):
            (self.directory / 'proposal.json').write_text(json.dumps(proposals.pop(0)))
        with mock.patch.object(agent, 'collect'), mock.patch.object(agent, 'propose', side_effect=propose), \
             mock.patch.object(agent, 'apply', side_effect=RuntimeError('Failed migration')):
            with self.assertRaises(agent.PolicyError): agent.run('update', self.directory)

    def test_http_regression_prevents_completion(self):
        def propose(*args):
            context=json.loads((self.directory / 'context.json').read_text())
            context['http_health']['https://service.test/']=500
            (self.directory / 'context.json').write_text(json.dumps(context))
            (self.directory / 'proposal.json').write_text(json.dumps(self.proposal(complete=True)))
        with mock.patch.object(agent, 'collect'), mock.patch.object(agent, 'propose', side_effect=propose):
            with self.assertRaises(RuntimeError): agent.run('update', self.directory)

    def test_dry_run_stops_after_validating_next_executable_stage(self):
        def propose(*args):
            (self.directory / 'proposal.json').write_text(json.dumps(self.proposal()))
        def apply(*args):
            (self.directory / 'summary.md').write_text('Dry run: no changes published')
        with mock.patch.dict(agent.os.environ, {'DRY_RUN':'true'}), mock.patch.object(agent, 'collect'), \
             mock.patch.object(agent, 'propose', side_effect=propose) as planner, \
             mock.patch.object(agent, 'apply', side_effect=apply):
            agent.run('update', self.directory)
        planner.assert_called_once()


class EvidencePrivacyTests(unittest.TestCase):
    def test_compaction_preserves_health_but_excludes_environment_and_large_annotations(self):
        data={'items':[{'metadata':{'name':'service','namespace':'test','annotations':{'last-applied':'long private details'}},
                        'spec':{'containers':[{'name':'app','image':'app:2.0','env':[{'name':'API_KEY','value':'should-not-leak'}]}]},
                        'status':{'phase':'Running','containerStatuses':[{'name':'app','ready':True,'restartCount':0}]}}]}
        compact=agent.compact_cluster(data)
        encoded=json.dumps(compact)
        self.assertNotIn('should-not-leak',encoded)
        self.assertNotIn('last-applied',encoded)
        self.assertEqual(compact['items'][0]['status']['phase'],'Running')

    def test_error_header_survives_large_cli_transcript(self):
        result=mock.Mock(stdout='',stderr='ERROR: provider rejected request\n'+'prompt-data '*10000)
        failure=agent.CommandFailure('Model failed',result)
        self.assertIn('provider rejected request',failure.output)
        self.assertLess(len(failure.output),15000)


if __name__ == '__main__':
    unittest.main()
