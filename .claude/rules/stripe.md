# Rules – Stripe

`terraform/stripe/live/` manages the one live Stripe account (`acct_1IAIb3ABYXXbGldT`) that every app sells
through — workspaced-ai, proklinator and pavel-usanli.online alike. The provider is Stripe's own `stripe/stripe`,
pinned exactly because it is 0.x. It authenticates with `STRIPE_API_KEY`, a restricted key named `terraform` with
Write on everything, kept apart from the apps' keys so it can be revoked without touching a running service.

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

Not everything has an API: branding, payouts, customer emails, Radar rules and team members stay in the Dashboard.
