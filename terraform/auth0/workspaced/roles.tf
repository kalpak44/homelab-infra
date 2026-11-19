# Roles are assigned to people in Auth0, next to the accounts themselves; the app takes them, and
# the names the sign-up form saved, from the ID token at each sign-in. Only `admin` means anything
# to it.
resource "auth0_role" "admin" {
  name        = "admin"
  description = "Manages the platform's mail in workspaced"
}

resource "auth0_action" "roles" {
  name    = "Roles and names in the ID token"
  runtime = "node22"
  deploy  = true

  supported_triggers {
    id      = "post-login"
    version = "v3"
  }

  # Auth0 drops a custom claim unless it is namespaced to a URL of our own. The names travel in
  # the ID token so the app shows them without asking the Management API on every page.
  code = <<-EOT
    const CLAIMS = "https://workspaced.online/";

    exports.onExecutePostLogin = async (event, api) => {
      const metadata = event.user.user_metadata ?? {};
      api.idToken.setCustomClaim(CLAIMS + "roles", event.authorization?.roles ?? []);
      api.idToken.setCustomClaim(CLAIMS + "given_name", String(metadata.given_name ?? ""));
      api.idToken.setCustomClaim(CLAIMS + "family_name", String(metadata.family_name ?? ""));
    };
  EOT
}
