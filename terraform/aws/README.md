# AWS

Account `039959484327` (`personal`), workload region `eu-central-1` (Frankfurt).
The existing `aws-admin` identity signs in through IAM Identity Center with the
`AdministratorAccess` permission set. Its SSO region is `eu-central-1` (Frankfurt).

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
export AWS_PROFILE=aws-admin
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
The provider rejects other account IDs. It creates no AWS resources. Future concerns
such as `personal/budgets` get their own directory and R2 state key, plus entries in
both workflow dropdowns, `terraform/Justfile` and the root README.

## R2 state and AWS credentials

Keep the existing `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT` and
`R2_BUCKET_NAME` environment variables. `terraform.sh` passes the R2 endpoint only
to the backend. The backend explicitly selects `homelab-r2` from `config`, whose
`credential_process` reads R2 credentials from the environment through
`r2-credentials.py`. AWS credentials remain available to the provider separately.

Run Terraform through `just` so the backend receives its bucket and endpoint.
All AWS leaf directories must stay at `aws/<account>/<concern>/` because the backend
config and credential helper paths are relative to that working directory.

## GitHub Actions (later setup)

The manual **AWS - Deploy** and **AWS - Destroy** workflows are prepared for OIDC.
Before using them:

1. Create or reuse the account's GitHub OIDC provider for
   `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`.
2. Create a Terraform IAM role with trust restricted to
   `repo:kalpak44/homelab-infra:ref:refs/heads/main` and that audience. Grant only
   the permissions needed by the Terraform concerns being deployed.
   Verify the repository's OIDC subject format when creating the trust policy;
   repositories using GitHub's newer format also include owner and repository IDs.
3. Set repository Actions **variable** `AWS_TERRAFORM_ROLE_ARN` to that role's ARN.
   Keep the existing R2 Actions secrets. No persistent AWS access-key secrets are needed.
4. Commit/push the workflows and dispatch `personal/account` to verify the connection.

The OIDC provider, role and repository variable have not been created by this setup.
Cost alerts will be a separate concern once a monthly amount and notification address
are chosen.
