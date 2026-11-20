# AWS

Account `039959484327` (`personal`), workload region `eu-central-1` (Frankfurt).
The existing `aws-admin` identity signs in through IAM Identity Center with the
`AdministratorAccess` permission set. Its SSO region is `eu-central-1` (Frankfurt).
Normal local Terraform runs use profile `aws-terraform`, which assumes the same
`homelab-infra-terraform` role as GitHub Actions. Both use identical permissions,
configuration, `just` commands and R2 state. The local-only IAM bootstrap selects
`aws-admin` separately so the shared deployment role cannot manage its own trust.

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
gets its own directory and R2 state key, plus entries in both workflow dropdowns,
`terraform/Justfile` and the root README.

## R2 state and AWS credentials

Keep the existing `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT` and
`R2_BUCKET_NAME` environment variables. `terraform.sh` passes the R2 endpoint only
to the backend. The backend explicitly selects `homelab-r2` from `config`, whose
`credential_process` reads R2 credentials from the environment through
`r2-credentials.py`. AWS credentials remain available to the provider separately.

Run Terraform through `just` so the backend receives its bucket and endpoint.
All AWS leaf directories must stay at `aws/<account>/<concern>/` because the backend
config and credential helper paths are relative to that working directory.

## GitHub Actions

The local bootstrap concern `personal/github-actions` manages:

- The GitHub OIDC provider, audience `sts.amazonaws.com`.
- Role `homelab-infra-terraform`, trusting only
  `repo:kalpak44/homelab-infra:ref:refs/heads/main` through OIDC and the account's
  AdministratorAccess SSO role through STS, with one-hour maximum sessions.
- Repository Actions variable `AWS_TERRAFORM_ROLE_ARN` containing the role ARN.

Create or restore this configuration with local `aws-admin` SSO and `GH_ADMIN_TOKEN`:

```bash
just --justfile terraform/Justfile plan-aws personal/github-actions
just --justfile terraform/Justfile deploy aws personal/github-actions
```

Its state is `homelab/aws/personal/github-actions.tfstate` in R2. This bootstrap
is intentionally excluded from CI dropdowns and rejected when `GITHUB_ACTIONS=true`:
the workflow role cannot change its own trust or permissions. Use a local admin
session to maintain it. The repository currently uses GitHub's default mutable OIDC
subject format; if that setting changes, update the trust condition accordingly.

Dispatch **AWS - Deploy** with `personal/account` to verify OIDC and R2 end to end.
The identity check requires no resource permissions. The shared role can also manage
the specific `personal-monthly-20-usd` budget. Add scoped permissions
to the bootstrap role as new Terraform concerns are introduced, then apply the
bootstrap locally before running those concerns in CI. Keep existing R2 Actions
secrets; no persistent AWS access-key secrets are needed.

## Monthly cost alert

`personal/budgets` manages an account-wide monthly USD 20 cost budget, across all
AWS regions and services. Its ACTUAL notification emails `pavel.usanli@gmail.com`
when the month's recorded charges are greater than USD 20. Taxes, support and
subscriptions are included; credits, discounts and refunds reduce the total.

```bash
just --justfile terraform/Justfile plan-aws personal/budgets
just --justfile terraform/Justfile deploy aws personal/budgets
```

The same concern is available in **AWS - Deploy** and **AWS - Destroy**. Its state is
`homelab/aws/personal/budgets.tfstate`. Apply the local `personal/github-actions`
bootstrap first when restoring the shared role's budget permissions.

The recipient must be verified through AWS User Notifications for account
`039959484327`; its existing email contact is active. If recreating the setup,
confirm the verification email while signed into this account. Budget evaluations
follow AWS billing updates; this alert does not stop services or cap spending.
