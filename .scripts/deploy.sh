#!/usr/bin/env bash
# Local equivalent of .github/workflows/deploy.yml
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
#   export HAPROXY_PUBLIC_IP=...
#   export HAPROXY_STATS_USER=...
#   export HAPROXY_STATS_PASSWORD=...
#   export ADGUARD_USERNAME=...
#   export ADGUARD_PASSWORD=...
#   export LETSENCRYPT_EMAIL=...
#   export VAULT_USERNAME=...
#   export VAULT_PASSWORD=...
#   export POSTGRESQL_DB=...
#   export POSTGRESQL_USER=...
#   export POSTGRESQL_PASSWORD=...
#   export PGADMIN_EMAIL=...
#   export PGADMIN_PASSWORD=...
#   export REDIS_PASSWORD=...
#   export REDIS_COMMANDER_USER=...
#   export REDIS_COMMANDER_PASSWORD=...
#   export RABBITMQ_USER=...
#   export RABBITMQ_PASSWORD=...
#   export PORTAINER_ADMIN_USERNAME=...
#   export PORTAINER_ADMIN_PASSWORD=...
#   export FLUX_GITHUB_TOKEN=...
#
# Usage:
#   ./deploy.sh <service> [--no-refresh]
#
# <service> options:
#   all
#   proxmox-dns
#   adguard | vault | postgres | redis | rabbitmq | portainer | haproxy | nfs | k3s
#   k3s/flux
#   k3s/flux/personal-web-page
#   k3s/flux/private-home-page
#   k3s/flux/mite-assistant-mcp
#   k3s/flux/crowdsec-web-ui
#   k3s/flux/traefik
#   k3s/flux/headlamp
#   k3s/flux/capacity-planner
#   k3s/flux/shopify-gpt-assistant
#   k3s/flux/bunker-game-app
#   k3s/flux/google-assistant-mcp
#   k3s/flux/data-source-connector-example
#   cloudflare-email

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Validate required env vars ────────────────────────────────────────────────
check_vars() {
  local missing=()
  for var in "$@"; do
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
}

CORE_TF_VARS=(
  R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_ENDPOINT
  R2_BUCKET_NAME CLOUDFLARE_API_TOKEN
  PROXMOX_ENDPOINT PROXMOX_USERNAME PROXMOX_PASSWORD
  SSH_PUBLIC_KEY SSH_PRIVATE_KEY
)
ANSIBLE_VARS=(
  ADGUARD_USERNAME ADGUARD_PASSWORD LETSENCRYPT_EMAIL
  VAULT_USERNAME VAULT_PASSWORD
  POSTGRESQL_DB POSTGRESQL_USER POSTGRESQL_PASSWORD
  PGADMIN_EMAIL PGADMIN_PASSWORD
  REDIS_PASSWORD REDIS_COMMANDER_USER REDIS_COMMANDER_PASSWORD
  RABBITMQ_USER RABBITMQ_PASSWORD
  PORTAINER_ADMIN_USERNAME PORTAINER_ADMIN_PASSWORD
  HAPROXY_STATS_USER HAPROXY_STATS_PASSWORD HAPROXY_PUBLIC_IP
  FLUX_GITHUB_TOKEN
)

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

# ── Decode SSH private key (stored as base64 in system env) ──────────────────
SSH_PRIVATE_KEY_DECODED="$(echo "$SSH_PRIVATE_KEY" | base64 --decode)"

# ── Map R2 vars → AWS env vars expected by Terraform S3 backend ──────────────
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_ENDPOINT_URL_S3="$R2_ENDPOINT"
export TF_VAR_ssh_private_key="$SSH_PRIVATE_KEY_DECODED"

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
  echo "$SSH_PRIVATE_KEY_DECODED" > ~/.ssh/id_ed25519
  chmod 600 ~/.ssh/id_ed25519
}

install_collections() {
  echo "▶  ansible-galaxy collection install"
  ansible-galaxy collection install -r "$ANSIBLE_DIR/requirements.yml"
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
    -e rabbitmq_user="$RABBITMQ_USER" \
    -e rabbitmq_password="$RABBITMQ_PASSWORD" \
    -e portainer_admin_username="$PORTAINER_ADMIN_USERNAME" \
    -e portainer_admin_password="$PORTAINER_ADMIN_PASSWORD" \
    -e haproxy_stats_user="$HAPROXY_STATS_USER" \
    -e haproxy_stats_password="$HAPROXY_STATS_PASSWORD" \
    -e flux_github_token="$FLUX_GITHUB_TOKEN" \
    -e cloudflare_api_token="$CLOUDFLARE_API_TOKEN"
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
case "$SERVICE" in

  proxmox-dns)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply -target=cloudflare_record.proxmox
    ;;

  adguard|vault|postgres|redis|rabbitmq|portainer|haproxy|nfs|k3s)
    check_vars "${CORE_TF_VARS[@]}" "${ANSIBLE_VARS[@]}"
    tf_init
    tf_apply
    write_ssh_key
    install_collections
    run_playbook "$SERVICE"
    ;;

  all)
    check_vars "${CORE_TF_VARS[@]}" "${ANSIBLE_VARS[@]}"
    tf_init
    tf_apply
    write_ssh_key
    install_collections
    for pb in adguard vault postgres redis rabbitmq portainer haproxy nfs k3s; do
      run_playbook "$pb"
    done
    ;;

  k3s/flux)
    check_vars "${ANSIBLE_VARS[@]}"
    write_ssh_key
    install_collections
    run_playbook flux
    ;;

  k3s/flux/personal-web-page)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply \
      -target=cloudflare_record.personal_web_page_apex \
      -target=cloudflare_record.personal_web_page_www
    ;;

  k3s/flux/private-home-page)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply -target=cloudflare_record.private_home_page
    ;;

  k3s/flux/mite-assistant-mcp)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply -target=cloudflare_record.mite_assistant
    ;;

  k3s/flux/crowdsec-web-ui)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply -target=cloudflare_record.crowdsec_web_ui
    ;;

  k3s/flux/traefik)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply -target=cloudflare_record.traefik
    ;;

  k3s/flux/headlamp)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply -target=cloudflare_record.headlamp
    ;;

  k3s/flux/capacity-planner)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply -target=cloudflare_record.capacity_planner
    ;;

  k3s/flux/shopify-gpt-assistant)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply -target=cloudflare_record.shopify_gpt_assistant
    ;;

  k3s/flux/bunker-game-app)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply -target=cloudflare_record.bunker_game_app
    ;;

  k3s/flux/google-assistant-mcp)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply -target=cloudflare_record.google_assistant
    ;;

  k3s/flux/data-source-connector-example)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply -target=cloudflare_record.data_source_connector_example
    ;;

  cloudflare-email)
    check_vars "${CORE_TF_VARS[@]}"
    tf_init
    tf_apply -target=module.cloudflare_email
    ;;

  *)
    echo "❌  Unknown service: $SERVICE" >&2
    exit 1
    ;;
esac

echo "✅  Done: $SERVICE"