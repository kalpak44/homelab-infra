#!/usr/bin/env python3
"""Apply an exact saved maintenance plan, refusing every deletion or replacement."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def validate(plan):
    if plan.get('errored') or any('delete' in r['change']['actions'] for r in plan.get('resource_changes', [])):
        raise ValueError('Maintenance cannot destroy or replace managed infrastructure')


def main():
    resource = (ROOT / 'terraform' / sys.argv[1]).resolve()
    if not resource.is_relative_to(ROOT / 'terraform') or not (resource / 'backend.tf').is_file():
        raise ValueError('Provide an existing per-resource Terraform directory')
    env = dict(os.environ)
    for key in ['AWS_PROFILE', 'AWS_DEFAULT_PROFILE', 'AWS_CONFIG_FILE', 'AWS_SESSION_TOKEN', 'AWS_SECURITY_TOKEN']:
        env.pop(key, None)
    env.update(AWS_ACCESS_KEY_ID=env['R2_ACCESS_KEY_ID'], AWS_SECRET_ACCESS_KEY=env['R2_SECRET_ACCESS_KEY'],
               AWS_ENDPOINT_URL_S3=env['R2_ENDPOINT'])
    mapping = {'cloudflare_api_token': 'CLOUDFLARE_API_TOKEN', 'proxmox_endpoint': 'PROXMOX_ENDPOINT',
        'proxmox_username': 'PROXMOX_USERNAME', 'proxmox_password': 'PROXMOX_PASSWORD',
        'ssh_public_key': 'SSH_PUBLIC_KEY', 'ssh_private_key': 'SSH_PRIVATE_KEY', 'host_password': 'HOST_PASSWORD',
        'github_owner': 'GH_OWNER', 'github_token': 'GH_ADMIN_TOKEN', 'deepseek_api_key': 'DEEPSEEK_APIKEY',
        'sonar_token': 'SONAR_TOKEN', 'android_keystore_base64': 'ANDROID_KEYSTORE_BASE64',
        'stripe_api_key': 'STRIPE_API_KEY', 'mailjet_api_key_public': 'MJ_APIKEY_PUBLIC',
        'mailjet_api_key_private': 'MJ_APIKEY_PRIVATE'}
    for key, source in mapping.items():
        if source in env:
            env['TF_VAR_' + key] = env[source]
    def terraform(*args):
        return subprocess.check_output(['terraform', *args], cwd=resource, env=env)
    # JSON plans contain secrets; never log them or leave them in the checkout.
    with tempfile.TemporaryDirectory(dir=os.environ.get('AGENT_DIRECTORY')) as directory:
        plan = str(Path(directory) / 'maintenance.tfplan')
        terraform('init', '-input=false', '-backend-config=bucket=' + env['R2_BUCKET_NAME'])
        terraform('plan', '-input=false', '-out=' + plan)
        validate(json.loads(terraform('show', '-json', plan)))
        if env.get('DRY_RUN') != 'true':
            terraform('apply', '-input=false', plan)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Terraform maintenance failed: ' + type(error).__name__)
        raise SystemExit(1)
