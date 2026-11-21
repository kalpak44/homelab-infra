#!/usr/bin/env python3
"""Prepare an isolated Codex home, run Markdown instructions, publish a redacted report."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def private_values(env):
    return {v for k, v in env.items() if len(v) >= 8 and re.search(
        r'PASSWORD|TOKEN|SECRET|APIKEY|PRIVATE_KEY|KEYSTORE', k)}


def redact(text, values):
    for value in sorted(values, key=len, reverse=True):
        text = text.replace(value, '[redacted]').replace(json.dumps(value)[1:-1], '[redacted]')
    return re.sub(r'(?s)-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----',
                  '[redacted private key]', text)


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
        env.update(HOME=str(home), CODEX_HOME=str(config), AGENT_SOURCE=str(ROOT),
                   AGENT_DIRECTORY=str(directory),
                   GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.hooksPath', GIT_CONFIG_VALUE_0=str(hooks))
        instructions = (ROOT / '.github/agent-prompts/maintenance-contract.md').read_text()
        instructions += '\n\n' + (ROOT / f'.github/agent-prompts/ai-{kind}-agent.md').read_text()
        instructions += '\n\nRun settings: ' + json.dumps({
            'kind': kind, 'dry_run': env.get('DRY_RUN', 'false'),
            'report': str(directory / 'result.md'), 'completion_marker': str(directory / 'SUCCESS'),
            'working_minutes': 150})
        # Tool transcripts can contain credentials. Keep them private, never upload or stream them.
        with (directory / 'codex.log').open('w') as log:
            result = subprocess.run(['codex', 'exec', '--ephemeral', '--sandbox', 'danger-full-access',
                '--output-last-message', str(directory / 'last-message.md'), '-'],
                input=instructions, text=True, cwd=ROOT, env=env, stdout=log, stderr=log, timeout=9600)
        text = (directory / 'result.md').read_text() if (directory / 'result.md').exists() else (
            (directory / 'last-message.md').read_text() if (directory / 'last-message.md').exists() else 'Codex produced no report.')
        success = result.returncode == 0 and (directory / 'SUCCESS').exists() and (directory / 'result.md').exists()
        from check_credentials import secret_values
        values |= {v.decode() for v in secret_values()}
        report.write_text(('Maintenance completed.\n\n' if success else 'Maintenance incomplete or failed.\n\n') + redact(text, values))
        if not success:
            print('Codex maintenance did not complete; see the sanitized report.', flush=True)
        return 0 if success else 1
    except Exception as error:
        # Exception payloads and subprocess logs may include secrets; expose type only.
        report.write_text('Maintenance failed during setup/execution: ' + type(error).__name__ + '.\n')
        print('Maintenance failed: ' + type(error).__name__, flush=True)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
