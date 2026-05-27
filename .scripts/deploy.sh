#!/usr/bin/env bash
# Local equivalent of .github/workflows/deploy.yml
#
# Usage:
#   ./deploy.sh <service> [--no-refresh]
#
# <service> options:
#   all
#   proxmox-dns
#   adguard | vault | postgres | redis | portainer | haproxy | nfs | k3s
#   k3s/flux
#   k3s/flux/personal-web-page
#   k3s/flux/private-home-page
#   k3s/flux/mite-assistant-mcp
#   k3s/flux/crowdsec-web-ui
#   k3s/flux/traefik
#   k3s/flux/headlamp
#   k3s/flux/capacity-planner
#   k3s/flux/shopify-gpt-assistant
#
# Examples:
#   ./deploy.sh all
#   ./deploy.sh postgres
#   ./deploy.sh k3s/flux/capacity-planner
#   ./deploy.sh k3s --no-refresh

set -euo pipefail

# ── Resolve script + repo root ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

# ── Load secrets ──────────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌  .env not found at $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=../.env
source "$ENV_FILE"

# ── Args ──────────────────────────────────────────────────────────────────────
SERVICE="${1:-}"
if [[ -z "$SERVICE" ]]; then
  echo "Usage: $0 <service> [--no-refresh]" >&2
  exit 1
fi

REFRESH_FLAG=""
if [[ "${2:-}" == "--no-refresh" ]]; then
  REFRESH_FLAG="-refresh=false"
fi

# ── Export env vars expected by Terraform ─────────────────────────────────────
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_ENDPOINT_URL_S3
export TF_VAR_ssh_private_key="$SSH_PRIVATE_KEY"

# ── Helpers ───────────────────────────────────────────────────────────────────
TF_DIR="$REPO_ROOT/terraform"
ANSIBLE_DIR="$REPO_ROOT/ansible"

tf_init() {
  echo "▶  terraform init"
  terraform -chdir="$TF_DIR" init \
    -backend-config="bucket=$R2_BUCKET_NAME"
}

tf_apply() {
  local extra_targets=("$@")
  echo "▶  terraform apply${extra_targets[*]:+ (targeted)}"
  terraform -chdir="$TF_DIR" apply -auto-approve $REFRESH_FLAG \
    "${extra_targets[@]+"${extra_targets[@]}"}" \
    -var proxmox_endpoint="$PROXMOX_ENDPOINT" \
    -var proxmox_username="$PROXMOX_USERNAME" \
    -var proxmox_password="$PROXMOX_PASSWORD" \
    -var ssh_public_key="$SSH_PUBLIC_KEY" \
    -var cloudflare_api_token="$CLOUDFLARE_API_TOKEN" \
    -var haproxy_public_ip="$HAPROXY_PUBLIC_IP"
}

write_ssh_key() {
  echo "▶  writing SSH key to ~/.ssh/id_ed25519"
  mkdir -p ~/.ssh
  echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
  chmod 600 ~/.ssh/id_ed25519
}

run_playbook() {
  local pb="$1"
  echo "▶  ansible-playbook $pb.yml"
  ansible-playbook \
    -i "$ANSIBLE_DIR/inventories/homelab.yml" \
    "$ANSIBLE_DIR/playbooks/$pb.yml" \
    -e adguard_username="$ADGUARD_USERNAME" \
    -e adguard_password="$ADGUARD_PASSWORD" \
    -e letsencrypt_email="$LETSENCRYPT_EMAIL" \
    -e vault_username="$VAULT_USERNAME" \
    -e vault_password="$VAULT_PASSWORD" \
    -e postgresql_db="$POSTGRESQL_DB" \
    -e postgresql_user="$POSTGRESQL_USER" \
    -e postgresql_password="$POSTGRESQL_PASSWORD" \
    -e pgadmin_email="$PGADMIN_EMAIL" \
    -e pgadmin_password="$PGADMIN_PASSWORD" \
    -e redis_password="$REDIS_PASSWORD" \
    -e redis_commander_user="$REDIS_COMMANDER_USER" \
    -e redis_commander_password="$REDIS_COMMANDER_PASSWORD" \
    -e portainer_admin_username="$PORTAINER_ADMIN_USERNAME" \
    -e portainer_admin_password="$PORTAINER_ADMIN_PASSWORD" \
    -e haproxy_stats_user="$HAPROXY_STATS_USER" \
    -e haproxy_stats_password="$HAPROXY_STATS_PASSWORD" \
    -e flux_github_token="$FLUX_GITHUB_TOKEN" \
    -e cloudflare_api_token="$CLOUDFLARE_API_TOKEN"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
case "$SERVICE" in

  # ── DNS-only (no Ansible) ──────────────────────────────────────────────────
  proxmox-dns)
    tf_init
    tf_apply -target=cloudflare_record.proxmox
    ;;

  # ── Infrastructure services (Terraform + Ansible) ─────────────────────────
  adguard|vault|postgres|redis|portainer|haproxy|nfs|k3s)
    tf_init
    tf_apply
    write_ssh_key
    run_playbook "$SERVICE"
    ;;

  # ── Full stack ────────────────────────────────────────────────────────────
  all)
    tf_init
    tf_apply
    write_ssh_key
    for pb in adguard vault postgres redis portainer haproxy nfs k3s; do
      run_playbook "$pb"
    done
    ;;

  # ── Flux bootstrap only (no Terraform) ────────────────────────────────────
  k3s/flux)
    write_ssh_key
    run_playbook flux
    ;;

  # ── In-cluster services — DNS record only ─────────────────────────────────
  k3s/flux/personal-web-page)
    tf_init
    tf_apply \
      -target=cloudflare_record.personal_web_page_apex \
      -target=cloudflare_record.personal_web_page_www
    ;;

  k3s/flux/private-home-page)
    tf_init
    tf_apply -target=cloudflare_record.private_home_page
    ;;

  k3s/flux/mite-assistant-mcp)
    tf_init
    tf_apply -target=cloudflare_record.mite_assistant
    ;;

  k3s/flux/crowdsec-web-ui)
    tf_init
    tf_apply -target=cloudflare_record.crowdsec_web_ui
    ;;

  k3s/flux/traefik)
    tf_init
    tf_apply -target=cloudflare_record.traefik
    ;;

  k3s/flux/headlamp)
    tf_init
    tf_apply -target=cloudflare_record.headlamp
    ;;

  k3s/flux/capacity-planner)
    tf_init
    tf_apply -target=cloudflare_record.capacity_planner
    ;;

  k3s/flux/shopify-gpt-assistant)
    tf_init
    tf_apply -target=cloudflare_record.shopify_gpt_assistant
    ;;

  *)
    echo "❌  Unknown service: $SERVICE" >&2
    echo "    Run '$0 --help' for options." >&2
    exit 1
    ;;
esac

echo "✅  Done: $SERVICE"