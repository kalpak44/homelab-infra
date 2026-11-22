#!/usr/bin/env python3
"""Read the operator SSH key from Vault into the job environment, masked, and decode
it into the given file for ssh-agent."""
import base64
import importlib.util
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    spec = importlib.util.spec_from_file_location(
        'operator_secrets', ROOT / 'ansible/03-vault/operator-secrets/secrets.py')
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    vault = helper.Vault(dict(os.environ))
    try:
        value = vault.request('GET', helper.SECRET)['data']['data'].get(helper.key('SSH_PRIVATE_KEY'), '')
    finally:
        vault.close()
    if not value or '\n' in value:
        raise RuntimeError('ssh-private-key is missing from Vault or is not single-line base64')
    # The mask must be registered before the value reaches any later step's log.
    print('::add-mask::' + value, flush=True)
    with open(os.environ['GITHUB_ENV'], 'a') as env:
        env.write('SSH_PRIVATE_KEY=' + value + '\n')
    descriptor = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'wb') as keyfile:
        keyfile.write(base64.b64decode(value, validate=True))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Vault responses can carry credentials; expose the type only.
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        print('Loading the operator key failed: ' + message, file=sys.stderr)
        sys.exit(1)
