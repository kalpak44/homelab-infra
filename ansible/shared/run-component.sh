#!/usr/bin/env bash
set -euo pipefail
ansible_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
component="${1:?Usage: run-component.sh <component-directory> [ansible-playbook arguments]}"
shift
component="$(cd -- "$component" && pwd)"
if [[ "$(dirname -- "$(dirname -- "$component")")" != "$ansible_dir" || ! -f "$component/playbook.yml" ]]; then
    echo "Select a numbered stage component directory." >&2
    exit 1
fi
if [[ ! -f "$component/.env" ]]; then
    echo "Copy $component/.env.example to $component/.env and fill its inputs." >&2
    exit 1
fi
# Each component owns its inputs; do not auto-discover the repository's root .env.
set -a
source "$component/.env"
set +a
: "${TARGET_HOST:?Set TARGET_HOST in this component's .env}"
: "${TARGET_USER:?Set TARGET_USER in this component's .env}"
export ANSIBLE_CONFIG="$ansible_dir/ansible.cfg"
exec ansible-playbook -i "$TARGET_HOST," -u "$TARGET_USER" "$component/playbook.yml" "$@"
