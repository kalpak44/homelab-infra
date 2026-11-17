# Rules – Stripe

**One Stripe account per app, one `terraform/stripe/<account>/<concern>/` dir per state** (`tax/`, `webhooks/`, and
`catalog/` once there is one), the same shape as `cloudflare/zones/<zone>/<concern>/`. An account's business name,
support email, receipts and statement descriptor are account-wide and have no API, so the only way for customers to
see each app as its own business is its own account. `workspaced` is `acct_1IAIb3ABYXXbGldT`. The provider is
Stripe's own `stripe/stripe`, pinned exactly because it is 0.x.

**Each account has its own `terraform` restricted key** (Write on everything), kept apart from the app's keys so it can
be revoked without touching a running service. Only `workspaced` is under Terraform, so its key is plain
`STRIPE_API_KEY` → `TF_VAR_stripe_api_key`; a second account needs its own name for both. `providers.tf` reads
`GET /v1/account` with the key and refuses to plan unless the ID matches — a key from the wrong account would
otherwise apply one app's config to another.

**An app's own API key cannot be managed here.** Stripe has no API for creating, rolling or revoking keys, so each
app's restricted key is made in the Dashboard and written to Vault by hand.

**Account settings stay in the Dashboard:** public details, branding, payouts, customer emails, Radar rules and team
members have no API for an account editing itself.

**Destroy archives; it never deletes.** Stripe has no delete for a price or a payment link, and refuses to delete a
product that has ever had a price, so removing one from the config leaves it archived and unbuyable. That is the
whole of what "removed" means here.

**A product's default price cannot be archived**, and the provider has no attribute to unset it, so removing a
product whose price is its default fails halfway. Clear it first — `POST /v1/products/<id>` with `default_price=` —
then apply.

**A price's currency and amount are immutable.** Changing either replaces the price: a new ID, the old one archived.
Point the matching `import` block at the new ID, or a rebuilt state adopts the archived one.

**The webhook signing secret is returned only on creation.** A replaced endpoint breaks workspaced-ai billing until
`stripe-webhook-secret` in `secret/workspaced-secrets` is updated, which is why the endpoint carries `prevent_destroy`.

