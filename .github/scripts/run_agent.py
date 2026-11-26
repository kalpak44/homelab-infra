#!/usr/bin/env python3
"""Prepare an isolated Codex home, run Markdown instructions, publish a redacted report."""
import json
import os
import queue
import signal
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def private_values(env):
    return {v for k, v in env.items() if len(v) >= 8 and re.search(
        r'PASSWORD|TOKEN|SECRET|APIKEY|PRIVATE_KEY|KEYSTORE', k)}


# Values fetched from Vault mid-run are unknown to the wrapper, so token shapes are scrubbed too.
TOKEN_PATTERNS = [
    (r'\b(?:hv[sbr]|gh[pousr])[._][A-Za-z0-9_-]{16,}', '[redacted]'),
    (r'\b(?:github_pat|sk|xox[abp])[_-][A-Za-z0-9_-]{16,}', '[redacted]'),
    (r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*', '[redacted]'),
    (r'(?i)(bearer\s+)[A-Za-z0-9._~+/=-]{12,}', r'\1[redacted]'),
    (r'(?i)((?:password|passwd|secret|token|api[_-]?key)["\']?\s*[=:]\s*["\']?)[^\s"\',;]{6,}',
     r'\1[redacted]'),
]


def redact(text, values):
    for value in sorted(values, key=len, reverse=True):
        text = text.replace(value, '[redacted]').replace(json.dumps(value)[1:-1], '[redacted]')
    for pattern, replacement in TOKEN_PATTERNS:
        text = re.sub(pattern, replacement, text)
    return re.sub(r'(?s)-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----',
                  '[redacted private key]', text)


def report_outcome(text):
    # Only the first Outcome line counts, so a later quote of another run cannot pass this one.
    for line in text.splitlines():
        plain = re.sub(r'[*`_]', '', line).strip().lstrip('-').strip()
        if plain.lower().startswith('outcome'):
            match = re.match(r'outcome\s*:\s*(SUCCESS|ATTENTION)\b', plain, re.IGNORECASE)
            return match.group(1).upper() if match else ''
    return ''


def excerpt(text, values, limit=600):
    text = ' '.join(redact(str(text), values).split())
    return text if len(text) <= limit else text[:limit] + ' …'


def progress_event(event, values=frozenset()):
    """Show the agent's narrative and plan redacted; never echo commands or tool output."""
    kind = event.get('type', '')
    if kind == 'turn.started':
        return 'Assessing evidence and choosing the next step'
    if kind in {'error', 'turn.failed'}:
        return 'Provider or agent error; details kept private for the final report'
    item = event.get('item', {})
    if item.get('type') == 'todo_list' and kind in {'item.started', 'item.updated', 'item.completed'}:
        steps = [('[x] ' if step.get('completed') else '[ ] ') + excerpt(step.get('text', ''), values, 120)
                 for step in item.get('items', [])]
        return 'Plan: ' + '; '.join(steps) if steps else None
    if kind not in {'item.started', 'item.completed'}:
        return None
    if item.get('type') == 'file_change':
        paths = [change.get('path', '') for change in item.get('changes', [])]
        paths = [os.path.relpath(path, ROOT) if os.path.isabs(path) else path for path in paths]
        return 'Editing ' + excerpt(', '.join(paths), values, 300) if paths else 'Updating repository source files'
    if item.get('type') in {'agent_message', 'reasoning'}:
        if kind != 'item.completed' or not item.get('text', '').strip():
            return None
        prefix = 'Agent: ' if item['type'] == 'agent_message' else 'Thinking: '
        return prefix + excerpt(item['text'], values)
    if item.get('type') != 'command_execution':
        return None
    command = item.get('command', '').lower()
    labels = [
        (r'check_credentials', 'Checking staged source for credentials'),
        (r'terraform_apply', 'Validating/applying a saved Terraform plan'),
        (r'(?:pct|qm) snapshot', 'Creating a guest recovery checkpoint'),
        (r'vault|operator.secrets', 'Accessing required Vault credentials privately'),
        (r'git push', 'Publishing validated source'),
        (r'git commit', 'Committing validated source'),
        (r'git (?:fetch|rebase)', 'Synchronizing repository changes'),
        (r'git diff', 'Reviewing source changes'),
        (r'syntax-check', 'Validating Ansible syntax'),
        (r'ansible-playbook|just.*(?:configure|os-update)', 'Applying Ansible maintenance'),
        (r'rollout status|kubectl.*wait', 'Waiting for cluster readiness'),
        (r'trivy|vulnerabilityreports|configauditreports', 'Inspecting Trivy security findings'),
        (r'check\.py', 'Validating CrowdSec rule wiring and blocklist digest'),
        (r'cscli', 'Inspecting CrowdSec alerts, decisions and metrics'),
        (r'blocked-ips|traffic\.(?:json|jsonl)|access.*log|/var/log/pods', 'Analyzing traffic and retained access-log evidence'),
        (r'kustomize|helm template', 'Validating deployment configuration'),
        (r'kubectl.*logs', 'Inspecting cluster logs and security diagnostics'),
        (r'kubectl', 'Inspecting Kubernetes resources'),
        (r'\bssh ', 'Inspecting a VM or LXC over SSH'),
        (r'curl|https://', 'Researching upstream sources'),
    ]
    label = next((label for pattern, label in labels if re.search(pattern, command)),
                 'Running a repository or maintenance command')
    if kind == 'item.completed':
        code = item.get('exit_code')
        return label + (' — exit ' + str(code) if isinstance(code, int) else ' — finished')
    return label + ' — started'


def execute_codex(args, instructions, env, directory, timeout=9600, heartbeat=30):
    started = last_visible = time.monotonic()
    values = private_values(env)
    events = queue.Queue()
    with (directory / 'codex.log').open('w') as raw, (directory / 'progress.log').open('w') as progress:
        def emit(message):
            nonlocal last_visible
            last_visible = time.monotonic()
            agent = env.get('AGENT_KIND', 'maintenance')
            agent = agent if agent in {'update', 'security'} else 'maintenance'
            line = datetime.now(timezone.utc).strftime('%H:%M:%S UTC') + ' | ' + agent + ' | ' + str(int(last_visible - started)) + 's | ' + message
            print(line, flush=True)
            progress.write(line + '\n')
            progress.flush()
        emit('Codex started; private tool output is excluded from this progress log')
        process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=raw, text=True, cwd=ROOT, env=env, start_new_session=True)
        def read_events():
            for line in process.stdout:
                events.put(line)
            events.put(None)
        threading.Thread(target=read_events, daemon=True).start()
        try:
            process.stdin.write(instructions)
            process.stdin.close()
            while True:
                if time.monotonic() - started >= timeout:
                    raise TimeoutError('Maintenance exceeded its execution budget')
                try:
                    line = events.get(timeout=min(heartbeat, 1))
                except queue.Empty:
                    line = ''
                if line is None:
                    break
                if line:
                    raw.write(line)
                    raw.flush()
                    try:
                        message = progress_event(json.loads(line), values)
                    except (ValueError, TypeError, AttributeError):
                        message = None
                    if message:
                        emit(message)
                if time.monotonic() - last_visible >= heartbeat:
                    emit('Still running; waiting for the active command or model response')
            code = process.wait(timeout=max(1, timeout - (time.monotonic() - started)))
            emit('Codex process exited with status ' + str(code))
            return code
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            process.stdout.close()


def main():
    kind, location = sys.argv[1:]
    if kind not in {'update', 'security'}:
        raise ValueError('Unknown agent kind')
    directory = Path(location).resolve()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(directory, 0o700)
    env = dict(os.environ)
    values = private_values(env)
    report = directory / 'summary.md'
    report.write_text('Maintenance did not finish. Inspect the failed workflow step.\n')
    try:
        home = directory / 'home'
        config = directory / 'codex'
        hooks = directory / 'hooks'
        for path in [home, config, hooks]:
            path.mkdir(mode=0o700, exist_ok=True)
        (config / 'config.toml').write_text(
            'model = ' + json.dumps(env.get('DEEPSEEK_MODEL', 'deepseek-v4-flash')) + '\n'
            'model_provider = "deepseek"\napproval_policy = "never"\nsandbox_mode = "danger-full-access"\n'
            '[shell_environment_policy]\ninherit = "all"\n'
            '[model_providers.deepseek]\nname = "DeepSeek"\n'
            'base_url = "https://api.deepseek.com/v1"\nenv_key = "DEEPSEEK_APIKEY"\nwire_api = "responses"\n')
        hook = hooks / 'pre-commit'
        hook.write_text('#!/bin/sh\nexec python3 "$AGENT_SOURCE/.github/scripts/check_credentials.py"\n')
        hook.chmod(0o700)
        # A read-only Go module cache would make the cleanup step's rm -rf fail.
        env.update(HOME=str(home), CODEX_HOME=str(config), AGENT_SOURCE=str(ROOT),
                   AGENT_DIRECTORY=str(directory), GOFLAGS='-modcacherw',
                   GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.hooksPath', GIT_CONFIG_VALUE_0=str(hooks))
        instructions = (ROOT / '.github/agent-prompts/maintenance-contract.md').read_text()
        instructions += '\n\n' + (ROOT / f'.github/agent-prompts/ai-{kind}-agent.md').read_text()
        instructions += '\n\nRun settings: ' + json.dumps({
            'kind': kind, 'dry_run': env.get('DRY_RUN', 'false'),
            'report': str(directory / 'result.md'), 'completion_marker': str(directory / 'SUCCESS'),
            'working_minutes': 150})
        code = execute_codex(['codex', 'exec', '--json', '--ephemeral', '--sandbox', 'danger-full-access',
            '--output-last-message', str(directory / 'last-message.md'), '-'], instructions, env, directory)
        text = (directory / 'result.md').read_text() if (directory / 'result.md').exists() else (
            (directory / 'last-message.md').read_text() if (directory / 'last-message.md').exists() else 'Codex produced no report.')
        marker = directory / 'SUCCESS'
        outcome = marker.read_text().strip().upper() if marker.exists() else ''
        # The agent sometimes writes a finished report and forgets the marker, which failed
        # verified work. The report's first Outcome line stands in; FAILED or none still fails.
        if not outcome and (directory / 'result.md').exists():
            outcome = report_outcome(text)
            if outcome:
                print('::warning title=Completion marker missing::Outcome ' + outcome
                      + ' taken from the report.', flush=True)
        finished = code == 0 and (directory / 'result.md').exists() and outcome in {'SUCCESS', 'ATTENTION'}
        from check_credentials import secret_values
        values |= {v.decode() for v in secret_values()}
        heading = ('Maintenance incomplete or failed.' if not finished else
                   'Maintenance completed with follow-ups that need a human.' if outcome == 'ATTENTION' else
                   'Maintenance completed.')
        report.write_text(heading + '\n\n' + redact(text, values))
        if not finished:
            print('Codex maintenance did not complete; see the sanitized report.', flush=True)
        elif outcome == 'ATTENTION':
            print('::warning title=Maintenance follow-ups::Work verified; open follow-ups need a human. '
                  'See the job summary.', flush=True)
        return 0 if finished else 1
    except Exception as error:
        # Exception payloads and subprocess logs may include secrets; expose type only.
        report.write_text('Maintenance failed during setup/execution: ' + type(error).__name__ + '.\n')
        print('Maintenance failed: ' + type(error).__name__, flush=True)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
