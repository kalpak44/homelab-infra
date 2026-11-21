#!/usr/bin/env python3
"""Reject credential files and known credential values in the staged Git snapshot."""
import os
import importlib.util
from pathlib import Path
import re
import subprocess


def secret_values():
    values = {v.encode() for k, v in os.environ.items() if len(v) >= 8 and re.search(
        r'PASSWORD|TOKEN|SECRET|APIKEY|PRIVATE_KEY|KEYSTORE', k)}
    # Fetch only for leak detection, never inject the archive into the agent environment.
    if os.environ.get('VAULT_ADDR') and os.environ.get('VAULT_USERNAME'):
        root = Path(__file__).resolve().parents[2]
        spec = importlib.util.spec_from_file_location('operator_secrets', root / 'ansible/03-vault/operator-secrets/secrets.py')
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        vault = helper.Vault(dict(os.environ))
        try:
            archive = vault.request('GET', helper.SECRET)['data']['data']
        finally:
            vault.close()
        values.update(str(v).encode() for k, v in archive.items() if len(str(v)) >= 8 and
                      re.search(r'password|token|secret|apikey|private.key|keystore', k, re.I))
    return values


def check():
    names = subprocess.check_output(['git', 'diff', '--cached', '--name-only', '--diff-filter=ACMR', '-z']).decode().split('\0')
    secrets = secret_values()
    failed = False
    for name in filter(None, names):
        path = Path(name)
        data = subprocess.check_output(['git', 'show', ':' + name])
        forbidden = ((path.name.startswith('.env') and path.name != '.env.example') or
                     path.suffix in {'.tfstate', '.tfplan', '.pem', '.key', '.p12'} or
                     path.name.startswith(('id_rsa', 'id_ed25519')))
        literal = any(value in data for value in secrets)
        private_key = re.search(rb'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----', data)
        if forbidden or literal or private_key:
            print('Credential check rejected staged file: ' + name)
            failed = True
    return 1 if failed else 0


if __name__ == '__main__':
    try:
        raise SystemExit(check())
    except Exception:
        print('Credential check could not finish; refusing commit without exposing values.')
        raise SystemExit(1)
