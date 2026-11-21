from copy import deepcopy
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import migrations


class MigrationPolicyTests(unittest.TestCase):
    def test_operations_are_fixed_recipes_not_shell(self):
        for operation in [
            {'type': 'shell', 'target': 'anything', 'layer': ''},
            {'type': 'configure', 'target': 'vault-lxc; extra-command', 'layer': ''},
            {'type': 'terraform', 'target': '../elsewhere', 'layer': 'cloudflare'},
            {'type': 'os-update', 'target': 'proxmox', 'layer': ''},
        ]:
            with self.assertRaises(ValueError): migrations.validate_operation(operation)
        migrations.validate_operation({'type': 'configure', 'target': 'vault-lxc', 'layer': ''})
        migrations.validate_operation({'type': 'os-update', 'target': 'k3s-2', 'layer': ''})

    def test_terraform_applies_cannot_destroy_or_replace(self):
        for actions in [['delete'], ['delete', 'create'], ['create', 'delete']]:
            with self.assertRaises(ValueError):
                migrations.safe_terraform_plan({'resource_changes': [{'change': {'actions': actions}}]})
        migrations.safe_terraform_plan({'resource_changes': [{'change': {'actions': ['update']}}]})

    def test_plan_requires_observed_upstream_evidence_and_recovery(self):
        proposal = {'changes': [{'path': 'file'}], 'operations': [], 'plan': {
            'target': 'vault', 'steps': ['migrate'], 'verification': ['healthy'],
            'recovery': ['matching checkpoint'], 'evidence_urls': ['https://github.com/hashicorp/vault/releases/tag/v3.0.0']}}
        context = {'release': proposal['plan']['evidence_urls'][0]}
        migrations.check_plan(proposal, context)
        for field in ['steps', 'verification', 'recovery', 'evidence_urls']:
            invalid = deepcopy(proposal); invalid['plan'][field] = []
            with self.assertRaises(ValueError): migrations.check_plan(invalid, context)
        with self.assertRaises(ValueError): migrations.check_plan(proposal, {})

    def test_research_cannot_reach_private_or_attacker_hosts(self):
        for url in ['http://github.com/docs', 'https://127.0.0.1/',
                    'https://example.invalid/instructions', 'https://github.com:8443/docs',
                    'https://user@github.com/docs']:
            with self.assertRaises(ValueError): migrations.safe_doc_url(url)
        self.assertEqual(migrations.safe_doc_url('https://docs.k3s.io/upgrades'), 'https://docs.k3s.io/upgrades')

    def test_major_downtime_snapshot_restarts_quiesced_service_on_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            api = mock.Mock()
            api.os.environ = {}
            api.ssh.side_effect = [mock.Mock(returncode=0), mock.Mock(returncode=1), mock.Mock(returncode=0)]
            api.CommandFailure = RuntimeError
            with self.assertRaises(RuntimeError):
                migrations.snapshot(api, [('vault-lxc', 'vault', 'pct', 201)],
                                    {'HOST_PASSWORD': 'test-only'}, Path(directory), quiesce=True)
            self.assertIn('systemctl stop vault', api.ssh.call_args_list[0].args[1])
            self.assertIn('systemctl start vault', api.ssh.call_args_list[2].args[1])
            self.assertNotIn('HOST_PASSWORD', api.os.environ)

    def test_targets_include_both_k3s_nodes(self):
        targets = migrations.targets_for([{'type': 'configure', 'target': 'k3s-cluster', 'layer': ''}])
        self.assertEqual({target[1] for target in targets}, {'k3s-1', 'k3s-2'})


if __name__ == '__main__': unittest.main()


class CheckpointRetentionTests(unittest.TestCase):
    def test_retains_three_recent_ai_snapshots_and_all_unrelated_snapshots(self):
        import json
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp)
            (directory/'recovery.jsonl').write_text(json.dumps({'host':'vault','kind':'pct','id':201,'snapshot':'ai-20261121010000'})+'\n')
            rows=[{'name':f'ai-202611210{i}0000','description':'AI-maintenance-checkpoint'} for i in range(5)]
            rows.append({'name':'operator-backup','description':'manual'})
            api=mock.Mock();api.os.environ={}
            api.ssh.side_effect=[mock.Mock(returncode=0,stdout=json.dumps(rows)),mock.Mock(returncode=0),mock.Mock(returncode=0)]
            self.assertEqual(migrations.prune_checkpoints(api,directory,{'HOST_PASSWORD':'test-only'}),[])
            deletes=[call.args[1] for call in api.ssh.call_args_list[1:]]
            self.assertEqual(len(deletes),2)
            self.assertTrue(all('delsnapshot' in command for command in deletes))
            self.assertFalse(any('operator-backup' in command for command in deletes))

    def test_security_rule_plan_may_use_private_traffic_evidence(self):
        proposal={'changes':[{'path':'rule'}],'operations':[], 'plan':{
            'target':'CrowdSec','steps':['block repeated attack'],'verification':['check decisions'],
            'recovery':['restore prior config'],'evidence_urls':[]}}
        migrations.check_plan(proposal, {'traffic_counts':{'93.184.215.14':30}},kind='security')
        with self.assertRaises(ValueError): migrations.check_plan(proposal, {},kind='security')
