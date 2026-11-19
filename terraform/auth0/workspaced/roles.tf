# Roles are assigned to people in Auth0, next to the accounts themselves; the app takes them from
# the ID token at each sign-in. Only `admin` means anything to it.
resource "auth0_role" "admin" {
  name        = "admin"
  description = "Manages the platform's mail in workspaced"
}

resource "auth0_action" "roles" {
  name    = "Roles in the ID token"
  runtime = "node22"
  deploy  = true

  supported_triggers {
    id      = "post-login"
    version = "v3"
  }

  # Auth0 drops a custom claim unless it is namespaced to a URL of our own.
  code = <<-EOT
    exports.onExecutePostLogin = async (event, api) => {
      api.idToken.setCustomClaim(
        "https://workspaced.online/roles",
        event.authorization?.roles ?? [],
      );
    };
  EOT
}
