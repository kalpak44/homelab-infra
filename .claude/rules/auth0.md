# Rules – Auth0

**One Auth0 tenant per app, one `terraform/auth0/<tenant>/` dir each.** `workspaced` is
`workspaced.eu.auth0.com`, in the EU region for GDPR — a tenant's region and name can never change. The tenant
holds identities only: passwords, MFA and profile live there, while roles, billing and workspaces stay in the app's
own database keyed by the Auth0 subject.

**Terraform signs in as the tenant's machine-to-machine app** (`AUTH0_CLIENT_ID` / `AUTH0_CLIENT_SECRET`, all
Management API scopes). It is created by hand and deliberately left out of the config, so no apply can revoke its
own access. Its grant needs *Client Access* permissions; *User-delegated Access* alone yields a token with no
scopes, which the Management API answers with a bare `401 Invalid token`.

**The tenant is on the free plan, which refuses rather than bills.** Password history, dictionary and
personal-info checks answer `403 missing entitlement: password-advanced-options`, so the connection keeps a
12-character minimum and leans on breached-password detection. The custom domain needs a verified card on file,
which is there; the plan is still Free. A template's `result_url` is Enterprise-only (`403 Customizations for resultUrl are not
allowed`), so where Auth0's own pages send the user back is the tenant's `default_redirection_uri` instead.

**The user database carries `prevent_destroy`**: deleting the connection deletes every account in it. Signups are
open, and the app refuses an email Auth0 has not verified, so a new account confirms its address before its first
sign-in. Accounts are managed in Auth0 alone; the app has no user administration of its own.

**Auth0's verification and reset mail is wrapped in the app's own mail layout** (`mail/layout.html.tftpl`, a copy
of `apps/api/src/main/resources/mail/layout.html` in workspaced-ai), so a change to one is a change to both. Its
logo is `https://workspaced.online/mail-logo.png`, published by the site, because Auth0 cannot embed an image.

**The app's client secret is copied into Vault by hand** — `just output auth0 workspaced client_secret`, then
`vault kv patch secret/workspaced-secrets auth0-client-secret=-`. It changes only when the client is recreated.

**MFA is optional, and an Action enforces it, not the Guardian policy.** The policy is `never`; the post-login
Action challenges users who have enrolled, and enrolls one whose authorization request carries the multi-factor
`acr_values`. Setting the policy to `all-applications` would make MFA mandatory for everyone.
