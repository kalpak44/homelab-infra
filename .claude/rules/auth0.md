# Rules – Auth0

**One Auth0 tenant per app, one `terraform/auth0/<tenant>/` dir each.** `workspaced` is
`workspaced.eu.auth0.com`, in the EU region for GDPR — a tenant's region and name can never change. The tenant
holds identities and roles: passwords, MFA and who is an `admin` live there, while billing and workspaces stay in
the app's own database keyed by the Auth0 subject.

**No personal data lives in the app's database.** `app_user` holds the Auth0 subject and the role, nothing else.
Email, first and last name and picture stay in Auth0: the sign-up form asks for the names (`profile.tf`, a prompt
partial plus a pre-registration Action that saves them to `user_metadata`), and the API reads and changes them
through the Management API, as the same `workspaced-ai` application under a grant limited to `read:users` and
`update:users`. The picture is Auth0's own — the Gravatar for the email, or one of the initials — because Auth0
holds a URL, not an image, and an upload would put the image back in our storage. Prompt partials need a page
template to exist, which is why `branding.tf` carries one that adds nothing but Auth0's own head and widget; a
partial created before it reads back as a 403 on every later refresh.

**Roles are Auth0 roles, assigned to people in the dashboard.** `roles.tf` defines `admin` and a post-login Action
that copies the user's roles into the ID token as `https://workspaced.online/roles` — Auth0 drops a custom claim
that is not namespaced to a URL. The app takes the role from that claim at every sign-in, so a change applies from
the user's next sign-in on. Assignments are data, not configuration, so Terraform never holds them.

**The sign-in round trip keeps nothing on a server.** The pending authorization request (state, nonce, PKCE
verifier) travels in an encrypted `workspaced_sign_in` cookie, so Auth0's callback may reach any API replica and
the ingress needs no session affinity. Do not reintroduce Spring's default session-backed store: with more than
one replica it fails every sign-in whose callback lands elsewhere.

**Auth0's sign-in and sign-up pages are themed like the app's own sign-in card** (`branding.tf`): the same zinc
palette, corners, logo and wording. The colours are copied from `apps/web`, so a change there is a change here.

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
