#!/usr/bin/env bash
# Local equivalent of .github/workflows/destroy.yml
#
# Secrets are read from environment variables — add them to ~/.zshrc or ~/.zshenv:
#
#   export R2_ACCESS_KEY_ID=...
#   export R2_SECRET_ACCESS_KEY=...
#   export R2_ENDPOINT=...           # https://<account-id>.r2.cloudflarestorage.com
#   export R2_BUCKET_NAME=...
#   export CLOUDFLARE_API_TOKEN=...
#   export PROXMOX_ENDPOINT=...
#   export PROXMOX_USERNAME=...
#   export PROXMOX_PASSWORD=...
#   export SSH_PUBLIC_KEY=...
#   export SSH_PRIVATE_KEY=...   # base64-encoded — store with: base64 -i ~/.ssh/id_ed25519 | tr -d '\n'
#
# Usage:
#   ./destroy.sh <service>
#
# <service> options:
#   all
#   proxmox-dns
#   adguard | vault | postgres | redis | rabbitmq | portainer | haproxy | nfs | k3s | dpi
#   cloudflare-email

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Validate required env vars ────────────────────────────────────────────────
REQUIRED_VARS=(
  R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_ENDPOINT
  R2_BUCKET_NAME CLOUDFLARE_API_TOKEN
  PROXMOX_ENDPOINT PROXMOX_USERNAME PROXMOX_PASSWORD
  SSH_PUBLIC_KEY SSH_PRIVATE_KEY
)

missing=()
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "❌  Missing environment variables:" >&2
  for v in "${missing[@]}"; do echo "    $v" >&2; done
  echo "    Add them to ~/.zshrc or ~/.zshenv and reload your shell." >&2
  exit 1
fi

# ── Args ──────────────────────────────────────────────────────────────────────
SERVICE="${1:-}"
if [[ -z "$SERVICE" ]]; then
  echo "Usage: $0 <service>" >&2
  exit 1
fi

# ── Decode SSH private key (stored as base64 in system env) ──────────────────
SSH_PRIVATE_KEY_DECODED="$(echo "$SSH_PRIVATE_KEY" | base64 --decode)"

# ── Map R2 vars → AWS env vars expected by Terraform S3 backend ──────────────
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_ENDPOINT_URL_S3="$R2_ENDPOINT"
export TF_VAR_ssh_private_key="$SSH_PRIVATE_KEY_DECODED"

# ── Resolve Terraform targets ─────────────────────────────────────────────────
case "$SERVICE" in
  proxmox-dns) TARGETS="-target=cloudflare_record.proxmox" ;;
  adguard)     TARGETS="-target=module.adguard"   ;;
  vault)       TARGETS="-target=module.vault"     ;;
  postgres)    TARGETS="-target=module.postgres"  ;;
  redis)       TARGETS="-target=module.redis"     ;;
  rabbitmq)    TARGETS="-target=module.rabbitmq"  ;;
  portainer)   TARGETS="-target=module.portainer" ;;
  haproxy)     TARGETS="-target=module.haproxy"   ;;
  nfs)         TARGETS="-target=module.nfs"       ;;
  k3s)              TARGETS="-target=module.k3s"              ;;
  dpi)              TARGETS="-target=module.dpi"              ;;
  cloudflare-email) TARGETS="-target=module.cloudflare_email" ;;
  all)              TARGETS=""                                ;;
  *)
    echo "❌  Unknown service: $SERVICE" >&2
    exit 1
    ;;
esac

# ── Safety prompt ─────────────────────────────────────────────────────────────
echo "⚠️   About to DESTROY: $SERVICE"
read -r -p "    Type the service name to confirm: " CONFIRM
if [[ "$CONFIRM" != "$SERVICE" ]]; then
  echo "❌  Aborted." >&2
  exit 1
fi

# ── Terraform Init + Destroy ──────────────────────────────────────────────────
TF_DIR="$REPO_ROOT/terraform"

echo "▶  terraform init"
terraform -chdir="$TF_DIR" init \
  -backend-config="bucket=$R2_BUCKET_NAME"

echo "▶  terraform destroy"
# shellcheck disable=SC2086
terraform -chdir="$TF_DIR" destroy -auto-approve \
  $TARGETS \
  -var proxmox_endpoint="$PROXMOX_ENDPOINT" \
  -var proxmox_username="$PROXMOX_USERNAME" \
  -var proxmox_password="$PROXMOX_PASSWORD" \
  -var ssh_public_key="$SSH_PUBLIC_KEY" \
  -var cloudflare_api_token="$CLOUDFLARE_API_TOKEN"

echo "✅  Done: $SERVICE destroyed"