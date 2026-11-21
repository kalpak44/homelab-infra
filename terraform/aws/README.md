# AWS

Account `039959484327` (`personal`), workload region `eu-central-1` (Frankfurt).
The existing `aws-admin` identity signs in through IAM Identity Center with the
`AdministratorAccess` permission set. Its SSO region is `eu-central-1` (Frankfurt).
Normal local Terraform runs use profile `aws-terraform`, which assumes the
`homelab-infra-terraform` role through local administrator SSO. The local-only IAM
bootstrap selects `aws-admin` separately so the deployment role cannot manage its
own trust or permissions.

## Local use

From the repository root, load the local, gitignored `.env` for direct CLI commands.
The `just` recipes load it automatically:

```bash
source .env
just --justfile terraform/Justfile aws-login
aws sts get-caller-identity
just --justfile terraform/Justfile plan-aws personal/account
just --justfile terraform/Justfile deploy aws personal/account
```

On another checkout, set these environment variables instead:

```bash
export AWS_CONFIG_FILE="terraform/aws/config"
export AWS_PROFILE=aws-terraform
export AWS_REGION=eu-central-1
export AWS_DEFAULT_REGION=eu-central-1
```

The CLI caches and refreshes temporary credentials in your home directory. Run
`aws-login` again when the SSO session expires. Clear any old `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN` variables before using SSO;
environment credentials take precedence over a selected profile.
`AWS_CONFIG_FILE` in `.env` is relative to the repository root; the Terraform wrapper
resolves that path before entering a concern directory. Run direct CLI commands from
the repository root.

`personal/account` reads the caller identity and exposes `account_id` and `caller_arn`.
The provider rejects other account IDs. It creates no AWS resources. Each concern
gets its own directory and R2 state key, plus an entry in `terraform/Justfile`
and documentation here. AWS provisioning runs locally.

## R2 state and AWS credentials

Keep the existing `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT` and
`R2_BUCKET_NAME` environment variables. `terraform.sh` passes the R2 endpoint only
to the backend. The backend explicitly selects `homelab-r2` from `config`, whose
`credential_process` reads R2 credentials from the environment through
`r2-credentials.py`. AWS credentials remain available to the provider separately.

Run Terraform through `just` so the backend receives its bucket and endpoint.
All AWS leaf directories must stay at `aws/<account>/<concern>/` because the backend
config and credential helper paths are relative to that working directory.

## Local IAM bootstrap

The concern `personal/iam-bootstrap` manages role `homelab-infra-terraform`:

- Trusts the account's AdministratorAccess SSO role through STS, with one-hour
  maximum sessions.
- Grants access to manage only the `personal-monthly-20-usd` budget.

Create or restore this configuration with local `aws-admin` SSO:

```bash
just --justfile terraform/Justfile plan-aws personal/iam-bootstrap
just --justfile terraform/Justfile deploy aws personal/iam-bootstrap
```

The directory retains the existing R2 state key
`homelab/aws/personal/github-actions.tfstate` to preserve managed resources across
the rename. Do not change that key without migrating the state.

Bootstrap operations require a local administrator session and are rejected when
`GITHUB_ACTIONS=true`. Add scoped permissions here as new Terraform concerns are
introduced, then apply the bootstrap locally before deploying those concerns.
AWS provisioning does not use GitHub OIDC or an Actions role variable.

## Monthly cost alert

`personal/budgets` manages an account-wide monthly USD 20 cost budget, across all
AWS regions and services. Its ACTUAL notification emails `pavel.usanli@gmail.com`
when the month's recorded charges are greater than USD 20. Taxes, support and
subscriptions are included; credits, discounts and refunds reduce the total.

```bash
just --justfile terraform/Justfile plan-aws personal/budgets
just --justfile terraform/Justfile deploy aws personal/budgets
```

Its state is `homelab/aws/personal/budgets.tfstate`. Apply the local
`personal/iam-bootstrap` concern first when restoring the deployment role's budget
permissions.

The recipient must be verified through AWS User Notifications for account
`039959484327`; its existing email contact is active. If recreating the setup,
confirm the verification email while signed into this account. Budget evaluations
follow AWS billing updates; this alert does not stop services or cap spending.
