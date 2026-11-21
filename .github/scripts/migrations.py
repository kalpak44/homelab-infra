"""Privileged migration operations; model proposals never execute arbitrary shell commands."""
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import urlparse
import urllib.request

HOSTS = {
    'adguard-lxc': [('adguard', 'pct', 200)], 'vault-lxc': [('vault', 'pct', 201)],
    'postgres-lxc': [('postgres', 'pct', 202)], 'redis-lxc': [('redis', 'pct', 204)],
    'nocobase-lxc': [('nocobase', 'pct', 207)], 'mihal-lxc': [('mihal', 'pct', 208)],
    'cloudflared-lxc': [('cloudflared', 'pct', 210)], 'prometheus-lxc': [('prometheus', 'pct', 211)],
    'grafana-lxc': [('grafana', 'pct', 212)], 'rustfs-lxc': [('rustfs', 'pct', 213)],
    'nfs-vm': [('nfs', 'qm', 301)], 'portainer-vm': [('portainer', 'qm', 302)],
    'k3s-cluster': [('k3s-1', 'qm', 110), ('k3s-2', 'qm', 111)],
}
SERVICES = {
    'adguard-lxc': ['AdGuardHome'], 'vault-lxc': ['vault'],
    'postgres-lxc': ['postgresql'], 'redis-lxc': ['redis-server'],
    'cloudflared-lxc': ['cloudflared'], 'mihal-lxc': ['cloudflared'],
    'prometheus-lxc': ['prometheus'], 'grafana-lxc': ['grafana-server'],
    'rustfs-lxc': ['rustfs'], 'nfs-vm': ['nfs-kernel-server'],
    'portainer-vm': ['docker'], 'k3s-cluster': ['k3s'],
}
DOC_HOSTS = {
    'github.com', 'raw.githubusercontent.com', 'kubernetes.io', 'docs.k3s.io',
    'www.postgresql.org', 'postgresql.org', 'redis.io', 'docs.docker.com',
    'developer.hashicorp.com', 'developers.cloudflare.com', 'docs.crowdsec.net',
    'hub.crowdsec.net', 'doc.traefik.io', 'metallb.io', 'external-secrets.io',
    'grafana.com', 'prometheus.io', 'helm.sh', 'docs.ansible.com',
    'registry.terraform.io', 'docs.portainer.io', 'docs.rustfs.com', 'hub.docker.com',
    'ubuntu.com', 'security.ubuntu.com', 'www.ubuntu.com', 'api.github.com',
    'charts.external-secrets.io', 'helm.vector.dev', 'crowdsecurity.github.io',
    'metallb.github.io', 'kubernetes-sigs.github.io', 'aquasecurity.github.io',
    'releases.hashicorp.com', 'docs.nocobase.com', 'www.nocobase.com', 'pve.proxmox.com',
}


def operator_environment(root):
    spec = importlib.util.spec_from_file_location('operator_secrets', root / 'ansible/03-vault/operator-secrets/secrets.py')
    helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    connection = dict(os.environ)
    connection.setdefault('VAULT_ADDR', 'https://vault.internal.pavel-usanli.online:8200')
    vault = helper.Vault(connection)
    try:
        data = vault.request('GET', helper.SECRET)['data']['data']
    finally:
        vault.close()
    # Credentials remain in the controller's memory/child environment, never model context.
    return {**os.environ, **{key.upper().replace('-', '_'): value for key, value in data.items()}}


def safe_doc_url(url):
    parsed = urlparse(url)
    if parsed.scheme != 'https' or parsed.hostname not in DOC_HOSTS or parsed.username or parsed.port not in [None, 443]:
        raise ValueError('Research is limited to approved public upstream documentation hosts')
    return url


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        safe_doc_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def research(urls):
    if len(urls) > 12:
        raise ValueError('Request at most twelve upstream documents per research round')
    output = {}
    opener = urllib.request.build_opener(SafeRedirect())
    for url in urls:
        safe_doc_url(url)
        try:
            with opener.open(urllib.request.Request(url, headers={'User-Agent': 'homelab-migration-agent'}), timeout=30) as response:
                text = response.read(2_000_000).decode(errors='replace')
        except Exception as error:
            output[url] = 'FETCH_FAILED:' + type(error).__name__ + ':' + str(getattr(error, 'code', 'network'))
            continue
        text = re.sub(r'<(?:script|style)\b[^>]*>.*?</(?:script|style)>', '', text, flags=re.S | re.I)
        text = re.sub(r'<[^>]+>', ' ', text)
        output[url] = re.sub(r'[ \t]+', ' ', text)[:100000]
    return output


def validate_operation(operation):
    kind, target, layer = operation['type'], operation['target'], operation['layer']
    if kind == 'configure':
        if target not in HOSTS and target != 'node-exporter':
            raise ValueError('Unknown host configuration target')
    elif kind == 'os-update':
        names = {host for group in HOSTS.values() for host, _, _ in group}
        if target not in names:
            raise ValueError('OS updates must target one supported guest at a time')
    elif kind == 'terraform':
        if layer not in ['cloudflare', 'proxmox', 'github', 'stripe', 'auth0'] or not re.fullmatch(r'[a-zA-Z0-9_.-]+(?:/[a-zA-Z0-9_.-]+)*', target):
            raise ValueError('Unsupported Terraform resource')
        if any(part in ['.', '..'] for part in Path(target).parts):
            raise ValueError('Invalid Terraform resource path')
    elif kind == 'packer':
        if target != 'workspace-vm':
            raise ValueError('Unknown Packer image')
    elif kind == 'scanners':
        if target != 'managed-repositories':
            raise ValueError('Unknown scanner update target')
    else:
        raise ValueError('Unknown migration operation')
    if kind != 'terraform' and layer:
        raise ValueError('Only Terraform operations take a layer')


def check_plan(proposal, context, kind="update"):
    plan = proposal['plan']
    if proposal['changes'] or proposal['operations']:
        if not plan['target'] or not plan['steps'] or not plan['verification'] or not plan['recovery']:
            raise ValueError('An executable migration requires steps, verification and recovery')
        traffic_evidence = kind == 'security' and (context.get('traffic_counts') or context.get('traffic_evidence_file') or context.get('cluster', {}).get('crowdsec_alerts'))
        if not plan['evidence_urls'] and not traffic_evidence:
            raise ValueError('An executable migration requires upstream or collected traffic evidence')
        known = json.dumps(context)
        for url in plan['evidence_urls']:
            safe_doc_url(url)
            if url not in known or context.get('research', {}).get(url, '').startswith('FETCH_FAILED:'):
                raise ValueError('Research the upstream migration evidence before proposing execution')
    for operation in proposal['operations']:
        validate_operation(operation)


def snapshot(api, targets, env, directory, quiesce=False):
    name = 'ai-' + datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')
    existing = [json.loads(line) for line in (directory / 'recovery.jsonl').read_text().splitlines()] if (directory / 'recovery.jsonl').exists() else []
    protected = {record['host'] for record in existing}
    records = []
    proxmox = os.environ.get('PROXMOX_SSH_HOST', '192.168.1.50')
    old_password = api.os.environ.get('HOST_PASSWORD')
    api.os.environ['HOST_PASSWORD'] = env['HOST_PASSWORD']
    try:
        for resource, host, tool, identifier in targets:
            if host in protected:
                records.extend(record for record in existing if record['host'] == host)
                continue
            stopped = []
            try:
                if quiesce and tool == 'pct':
                    for service in SERVICES.get(resource, []):
                        result = api.ssh(proxmox, f'{tool} exec {identifier} -- systemctl stop {service}')
                        if result.returncode:
                            raise RuntimeError('Could not quiesce the service before its snapshot')
                        stopped.append(service)
                result = api.ssh(proxmox, f'{tool} snapshot {identifier} {name} --description AI-maintenance-checkpoint')
                if result.returncode:
                    raise api.CommandFailure('Required guest snapshot failed; migration was not started', result)
                records.append({'host': host, 'kind': tool, 'id': identifier, 'snapshot': name})
            finally:
                for service in stopped:
                    if api.ssh(proxmox, f'{tool} exec {identifier} -- systemctl start {service}').returncode:
                        raise RuntimeError('Service did not restart after its consistent snapshot')
    finally:
        if old_password is None: api.os.environ.pop('HOST_PASSWORD', None)
        else: api.os.environ['HOST_PASSWORD'] = old_password
    with (directory / 'recovery.jsonl').open('a') as output:
        for record in records: output.write(json.dumps(record) + '\n')
    return records


def targets_for(operations):
    targets = {}
    for operation in operations:
        kind, target = operation['type'], operation['target']
        if kind == 'configure':
            groups = HOSTS.values() if target == 'node-exporter' else [HOSTS[target]]
            for group in groups:
                for host, tool, identifier in group:
                    resource = next(name for name, members in HOSTS.items() if (host, tool, identifier) in members)
                    targets[host] = (resource, host, tool, identifier)
        elif kind == 'os-update':
            for resource, members in HOSTS.items():
                for host, tool, identifier in members:
                    if host == target: targets[host] = (resource, host, tool, identifier)
    return list(targets.values())


def deployment_environment(values):
    env = dict(values)
    for key, value in values.items():
        if isinstance(value, str) and len(value) >= 8 and re.search(r'PASSWORD|TOKEN|SECRET|APIKEY|PRIVATE_KEY|KEYSTORE', key):
            print('::add-mask::' + value)
    for key in ['AWS_PROFILE', 'AWS_DEFAULT_PROFILE', 'AWS_CONFIG_FILE', 'AWS_SESSION_TOKEN', 'AWS_SECURITY_TOKEN']:
        env.pop(key, None)
    env['AWS_ACCESS_KEY_ID'] = values.get('R2_ACCESS_KEY_ID', '')
    env['AWS_SECRET_ACCESS_KEY'] = values.get('R2_SECRET_ACCESS_KEY', '')
    env['AWS_ENDPOINT_URL_S3'] = values.get('R2_ENDPOINT', '')
    mapping = {
        'cloudflare_api_token': 'CLOUDFLARE_API_TOKEN', 'proxmox_endpoint': 'PROXMOX_ENDPOINT',
        'proxmox_username': 'PROXMOX_USERNAME', 'proxmox_password': 'PROXMOX_PASSWORD',
        'ssh_public_key': 'SSH_PUBLIC_KEY', 'ssh_private_key': 'SSH_PRIVATE_KEY',
        'host_password': 'HOST_PASSWORD', 'github_owner': 'GH_OWNER', 'github_token': 'GH_ADMIN_TOKEN',
        'deepseek_api_key': 'DEEPSEEK_APIKEY', 'sonar_token': 'SONAR_TOKEN',
        'android_keystore_base64': 'ANDROID_KEYSTORE_BASE64', 'stripe_api_key': 'STRIPE_API_KEY',
        'mailjet_api_key_public': 'MJ_APIKEY_PUBLIC', 'mailjet_api_key_private': 'MJ_APIKEY_PRIVATE',
    }
    for name, source in mapping.items(): env['TF_VAR_' + name] = values.get(source, '')
    return env


def safe_terraform_plan(plan):
    for resource in plan.get('resource_changes', []):
        if 'delete' in resource['change']['actions']:
            raise ValueError('Automatic maintenance cannot destroy or replace managed infrastructure')
    if plan.get('errored'):
        raise ValueError('Terraform plan failed')


def execute(api, operations, directory, env):
    env = deployment_environment(env)
    for operation in operations:
        kind, target, layer = operation['type'], operation['target'], operation['layer']
        validate_operation(operation)
        if kind == 'configure':
            api.command(['just', '--justfile', 'ansible/Justfile', 'configure', target], env=env, timeout=2700)
        elif kind == 'os-update':
            api.command(['just', '--justfile', 'ansible/Justfile', 'os-update', target], env=env, timeout=2700)
        elif kind == 'terraform':
            path = api.ROOT / 'terraform' / layer / target
            if not (path / 'backend.tf').is_file(): raise ValueError('Terraform target has no resource backend')
            tfenv = deployment_environment(env)
            api.command(['terraform', 'init', '-upgrade', '-input=false', '-backend-config=bucket=' + env['R2_BUCKET_NAME']], cwd=path, env=tfenv, timeout=300)
            saved = directory / 'migration.tfplan'
            try:
                api.command(['terraform', 'plan', '-input=false', '-out=' + str(saved)], cwd=path, env=tfenv, timeout=600)
                plan = json.loads(api.command(['terraform', 'show', '-json', str(saved)], cwd=path, env=tfenv).stdout)
                safe_terraform_plan(plan)
                api.command(['terraform', 'apply', '-input=false', str(saved)], cwd=path, env=tfenv, timeout=1800)
            finally:
                saved.unlink(missing_ok=True)
        elif kind == 'packer':
            api.command(['just', '--justfile', 'packer/Justfile', 'build', target], env=env, timeout=2700)
        elif kind == 'scanners':
            api.command(['just', '--justfile', 'terraform/Justfile', 'bump-scanners'], env=env, timeout=1800)


def render_chart(api, work, change, directory):
    import yaml
    release = yaml.safe_load(change['content'])
    chart = release['spec']['chart']['spec']
    namespace = release['metadata'].get('namespace', 'default')
    name = release['metadata']['name']
    repositories = [yaml.safe_load(path.read_text()) for path in (work / 'gitops/clusters/homelab/infrastructure').glob('*/helmrepository.yaml')]
    repository = next((doc for doc in repositories if doc['metadata']['name'] == chart['sourceRef']['name']), None)
    if repository is None: raise ValueError('Chart migration has no known HelmRepository')
    values = directory / ('values-' + name + '.yaml')
    values.write_text(yaml.safe_dump(release['spec'].get('values', {})))
    args = ['helm', 'template', name, chart['chart'], '--repo', repository['spec']['url'],
            '--version', chart['version'], '--namespace', namespace, '--include-crds', '-f', str(values)]
    # Resolve ConfigMap-sourced file values from rendered Kustomize output, without reading live secrets.
    manifests = api.command(['kubectl', 'kustomize', str((work / change['path']).parent)], cwd=work).stdout
    maps = {doc['metadata']['name']: doc for doc in yaml.safe_load_all(manifests)
            if isinstance(doc, dict) and doc.get('kind') == 'ConfigMap'}
    for i, ref in enumerate(release['spec'].get('valuesFrom', [])):
        value = directory / ('value-' + name + '-' + str(i))
        if ref.get('kind') == 'Secret':
            value.write_text('validation-placeholder')
        else:
            value.write_text(maps[ref['name']]['data'][ref.get('valuesKey', 'values.yaml')])
        if ref.get('targetPath'):
            args.extend(['--set-file', ref['targetPath'].replace('\\\\', '\\') + '=' + str(value)])
        else:
            args.extend(['-f', str(value)])
    api.command(args, cwd=work, timeout=180)


def prune_checkpoints(api, directory, env):
    path = directory / 'recovery.jsonl'
    if not path.exists(): return []
    records = {row['host']: row for row in map(json.loads, path.read_text().splitlines())}
    warnings = []
    original = api.os.environ.get('HOST_PASSWORD')
    api.os.environ['HOST_PASSWORD'] = env['HOST_PASSWORD']
    try:
        for record in records.values():
            kind = 'qemu' if record['kind'] == 'qm' else 'lxc'
            endpoint = '/nodes/$(hostname)/' + kind + '/' + str(record['id']) + '/snapshot'
            result = api.ssh(os.environ.get('PROXMOX_SSH_HOST', '192.168.1.50'),
                             'pvesh get ' + endpoint + ' --output-format json')
            if result.returncode:
                warnings.append('Could not enumerate AI checkpoints for ' + record['host'])
                continue
            snapshots = [row['name'] for row in json.loads(result.stdout)
                         if re.fullmatch(r'ai-\d{14}', row.get('name', '')) and
                         row.get('description') == 'AI-maintenance-checkpoint']
            for old in sorted(snapshots, reverse=True)[3:]:
                if api.ssh(os.environ.get('PROXMOX_SSH_HOST', '192.168.1.50'),
                           record['kind'] + ' delsnapshot ' + str(record['id']) + ' ' + old).returncode:
                    warnings.append('Retained an older checkpoint for ' + record['host'])
    finally:
        if original is None: api.os.environ.pop('HOST_PASSWORD', None)
        else: api.os.environ['HOST_PASSWORD'] = original
    return warnings
