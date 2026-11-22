#!/usr/bin/env bash
# Writes the base64 SSH_PRIVATE_KEY to the given file, mode 600. Fails on anything that
# is not a usable key, so a bad value stops the run instead of reaching a host.
set -euo pipefail
dest="${1:?Usage: operator-key.sh <file>}"
: "${SSH_PRIVATE_KEY:?Set SSH_PRIVATE_KEY to the base64 of the operator private key}"
umask 077
if ! printf '%s' "$SSH_PRIVATE_KEY" | base64 -d > "$dest" 2>/dev/null \
    || ! ssh-keygen -y -f "$dest" >/dev/null 2>&1; then
  rm -f "$dest"
  echo "SSH_PRIVATE_KEY is not a base64-encoded private key" >&2
  exit 1
fi
