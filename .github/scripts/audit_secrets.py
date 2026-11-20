#!/usr/bin/env python3
"""Audit Actions secret names against published and proposed consumers before deletion."""
import argparse
import base64
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REPO = 'kalpak44/homelab-infra'
REFERENCE = re.compile(r'secrets\.([A-Z][A-Z0-9_]*)')


def gh(*args):
    result = subprocess.run(['gh', *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('GitHub request failed; no secret values were printed')
    return result.stdout


def audit(delete=False):
    local = set()
    for path in (ROOT / '.github').rglob('*'):
        if path.suffix in ['.yml', '.yaml'] and ('workflows' in path.parts or 'actions' in path.parts):
            local.update(REFERENCE.findall(path.read_text()))
    info = json.loads(gh('api', 'repos/' + REPO))
    branch = info['default_branch']
    tree = json.loads(gh('api', f'repos/{REPO}/git/trees/{branch}?recursive=1'))
    if tree.get('truncated'):
        raise RuntimeError('Published tree is incomplete; refusing cleanup')
    remote = set()
    for entry in tree['tree']:
        path = entry['path']
        if entry['type'] == 'blob' and path.startswith(('.github/workflows/', '.github/actions/')) and path.endswith(('.yml', '.yaml')):
            blob = json.loads(gh('api', f'repos/{REPO}/git/blobs/' + entry['sha']))
            remote.update(REFERENCE.findall(base64.b64decode(blob['content']).decode()))
    existing = {s['name'] for s in json.loads(gh('secret', 'list', '--repo', REPO, '--json', 'name'))}
    existing.discard('GITHUB_TOKEN')
    candidates = sorted(existing - local - remote)
    result = {'required_by_proposed_workflows': sorted(local - {'GITHUB_TOKEN'}),
              'missing_for_proposed_workflows': sorted(local - existing - {'GITHUB_TOKEN'}),
              'unused_now': candidates, 'removable_after_publish': sorted((existing & remote) - local),
              'deleted': [], 'retained_without_vault_backup': []}
    if delete and candidates:
        spec = importlib.util.spec_from_file_location('operator_secrets', ROOT / 'ansible/03-vault/operator-secrets/secrets.py')
        helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
        # Only names and backup presence are reported, never local or Vault secret values.
        env = {**helper.local_values(), **os.environ}
        vault = helper.Vault(env)
        try:
            data = vault.request('GET', helper.SECRET)['data']['data']
            for name in candidates:
                if not data.get(helper.key(name)):
                    result['retained_without_vault_backup'].append(name)
                    continue
                gh('secret', 'delete', name, '--repo', REPO)
                result['deleted'].append(name)
        finally:
            vault.close()
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--delete-unused', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(audit(args.delete_unused), indent=2))
    except Exception:
        print('Audit/cleanup failed; inspect connectivity and authentication. No secret values were printed.')
        raise SystemExit(1)
