# AWS

Account `039959484327` (`personal`), workload region `eu-central-1` (Frankfurt).
Authentication is split in two, and `terraform.sh` enforces which one a concern gets:

| Concern | Credential | Command |
|---------|------------|---------|
| `<account>/admin` | `aws-admin` SSO (IAM Identity Center, `AdministratorAccess`), browser sign-in | `just deploy-aws-admin <account>` |
| every other concern | key of IAM user `homelab-infra-terraform` | `just deploy aws <account>/<concern>` |

The admin concern creates that user, its policy and its key, so the key can never widen
its own permissions. The wrapper clears the key for admin runs and refuses SSO for the
others, and refuses admin runs in GitHub Actions.

## Local use

The `just` recipes load the gitignored root `.env`. Workload concerns need only the key:

```bash
just --justfile terraform/Justfile plan-aws personal/account
just --justfile terraform/Justfile deploy aws personal/budgets
```

| Variable | Where it lives |
|----------|----------------|
| `AWS_TERRAFORM_ACCESS_KEY_ID` | root `.env`; Vault `secret/homelab-infra-secrets` key `aws-terraform-access-key-id` |
| `AWS_TERRAFORM_SECRET_ACCESS_KEY` | root `.env`; Vault key `aws-terraform-secret-access-key` |

The wrapper maps them to `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` only for the run,
so other tools never see an AWS key in the environment. `AWS_CONFIG_FILE` in `.env` is
relative to the repository root; the wrapper resolves it before entering a concern.

`personal/account` reads the caller identity and exposes `account_id` and `caller_arn`.
The provider rejects other account IDs. It creates no AWS resources. Each concern
gets its own directory and R2 state key, plus an entry in `terraform/Justfile`
and documentation here.

## R2 state and AWS credentials

Keep the existing `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT` and
`R2_BUCKET_NAME` environment variables. `terraform.sh` passes the R2 endpoint only
to the backend. The backend explicitly selects `homelab-r2` from `config`, whose
`credential_process` reads R2 credentials from the environment through
`r2-credentials.py`. AWS credentials remain available to the provider separately.

Run Terraform through `just` so the backend receives its bucket and endpoint.
All AWS leaf directories must stay at `aws/<account>/<concern>/` because the backend
config and credential helper paths are relative to that working directory.

## Admin concern and the Terraform key

`personal/admin` manages IAM user `homelab-infra-terraform`, an inline policy allowing
only the `personal-monthly-20-usd` budget, and the user's access key. Add permissions
here as new concerns are introduced, then apply it before deploying them.

```bash
just --justfile terraform/Justfile aws-login
just --justfile terraform/Justfile plan-aws-admin personal
just --justfile terraform/Justfile deploy-aws-admin personal
just --justfile terraform/Justfile output aws personal/admin terraform_access_key_id
just --justfile terraform/Justfile output aws personal/admin terraform_secret_access_key
```

Copy both outputs into `.env` and Vault (`just --justfile ansible/Justfile secrets-store
--replace-existing`, or `vault kv patch`). To rotate, apply the admin concern with
`-replace=aws_iam_access_key.terraform` and copy the new pair the same way; the old key
stops working on that apply. The secret is also held in the R2 state, like every other
Terraform-generated credential here.

The directory keeps the R2 state key `homelab/aws/personal/github-actions.tfstate`
from before two renames. Do not change that key without migrating the state.

## Monthly cost alert

`personal/budgets` manages an account-wide monthly USD 20 cost budget, across all
AWS regions and services. Its ACTUAL notification emails `pavel.usanli@gmail.com`
when the month's recorded charges are greater than USD 20. Taxes, support and
subscriptions are included; credits, discounts and refunds reduce the total.

```bash
just --justfile terraform/Justfile plan-aws personal/budgets
just --justfile terraform/Justfile deploy aws personal/budgets
```

Its state is `homelab/aws/personal/budgets.tfstate`. Apply `personal/admin` first
when restoring the Terraform user's budget permissions.

The recipient must be verified through AWS User Notifications for account
`039959484327`; its existing email contact is active. If recreating the setup,
confirm the verification email while signed into this account. Budget evaluations
follow AWS billing updates; this alert does not stop services or cap spending.
