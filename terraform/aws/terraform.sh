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
# <account>/admin manages the IAM user every other concern deploys as, so it runs only
# with a browser-authenticated admin session; everything else runs only with that user's key.
# Reading outputs touches only the R2 state and needs neither.
if [[ "$resource" == */admin && "$action" != output ]]; then
  if [ "${AWS_ADMIN_RUN:-}" != 1 ]; then
    echo "Run admin concerns with: just deploy-aws-admin ${resource%/admin}" >&2
    exit 1
  fi
  if [ "${GITHUB_ACTIONS:-}" = true ]; then
    echo "Admin concerns require a local SSO session." >&2
    exit 1
  fi
fi
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
# Environment keys outrank a profile in the SDK, so each mode clears the other's.
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE AWS_DEFAULT_PROFILE
if [ "$action" = output ]; then
  :
elif [[ "$resource" == */admin ]]; then
  export AWS_PROFILE=aws-admin
else
  : "${AWS_TERRAFORM_ACCESS_KEY_ID:?AWS_TERRAFORM_ACCESS_KEY_ID is required; see terraform/aws/README.md}"
  : "${AWS_TERRAFORM_SECRET_ACCESS_KEY:?AWS_TERRAFORM_SECRET_ACCESS_KEY is required}"
  export AWS_ACCESS_KEY_ID="$AWS_TERRAFORM_ACCESS_KEY_ID"
  export AWS_SECRET_ACCESS_KEY="$AWS_TERRAFORM_SECRET_ACCESS_KEY"
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
