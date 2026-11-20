#!/usr/bin/env bash
set -euo pipefail

action=${1:?action is required}
resource=${2:?resource is required}
case "$action" in
  deploy|destroy|plan|output) ;;
  *) echo "Unknown AWS action: $action" >&2; exit 1 ;;
esac
if [[ ! "$resource" =~ ^[a-z0-9-]+/[a-z0-9-]+$ ]]; then
  echo "AWS resource must be <account>/<concern>" >&2
  exit 1
fi
if [ "$resource" = personal/github-actions ] && [ "${GITHUB_ACTIONS:-}" = true ]; then
  echo "GitHub OIDC bootstrap requires a local administrator session." >&2
  exit 1
fi
export TF_VAR_github_token="${GH_ADMIN_TOKEN:-}"

: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID is required}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY is required}"
: "${R2_ENDPOINT:?R2_ENDPOINT is required}"
: "${R2_BUCKET_NAME:?R2_BUCKET_NAME is required}"

aws_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export AWS_CONFIG_FILE="${AWS_CONFIG_FILE:-$aws_dir/config}"
if [[ "$AWS_CONFIG_FILE" != /* ]]; then
  export AWS_CONFIG_FILE="$aws_dir/../../$AWS_CONFIG_FILE"
fi
export AWS_REGION="${AWS_REGION:-eu-central-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ -z "${AWS_WEB_IDENTITY_TOKEN_FILE:-}" ]; then
  if [ "$resource" = personal/github-actions ]; then
    export AWS_PROFILE="${AWS_BOOTSTRAP_PROFILE:-aws-admin}"
  else
    export AWS_PROFILE="${AWS_PROFILE:-aws-terraform}"
  fi
fi

# R2's endpoint is backend-only; inheriting it would send AWS S3 calls to Cloudflare.
unset AWS_ENDPOINT_URL AWS_ENDPOINT_URL_S3
cd "$aws_dir/$resource"
init_args=(-backend-config="bucket=$R2_BUCKET_NAME"
           -backend-config="endpoints={s3=\"$R2_ENDPOINT\"}" -input=false)
if [ "$action" = output ]; then
  terraform init "${init_args[@]}" >/dev/null
  terraform output -raw "${3:?output name is required}" 2>/dev/null || terraform output -json "$3"
else
  terraform init "${init_args[@]}"
  case "$action" in
    deploy) terraform apply -auto-approve -input=false ;;
    destroy) terraform destroy -auto-approve -input=false ;;
    plan) terraform plan -input=false ;;
  esac
fi
