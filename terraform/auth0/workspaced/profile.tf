# A user's name lives in Auth0, never in the app's database: asked for on the sign-up form, kept
# in user_metadata, and read and changed by the API through the Management API.
resource "auth0_prompt_screen_partial" "signup" {
  prompt_type = "signup"
  screen_name = "signup"

  # The fields need the page template to exist.
  depends_on = [auth0_branding.this]

  # Fields named ulp-* reach the pre-registration Action below in the request body.
  insertion_points {
    form_content_start = <<-EOT
      <div class="ulp-field">
        <label for="ulp-given-name">First name</label>
        <input type="text" id="ulp-given-name" name="ulp-given-name" maxlength="100" autocomplete="given-name">
      </div>
      <div class="ulp-field">
        <label for="ulp-family-name">Last name</label>
        <input type="text" id="ulp-family-name" name="ulp-family-name" maxlength="100" autocomplete="family-name">
      </div>
    EOT
    # Where the app's own sign-in card used to ask for it, now that sign-up starts here. The tips
    # line tells people before the account exists that tips are emailed unless turned off.
    form_content_end = <<-EOT
      <p class="ulp-consent">By creating an account you agree to the
        <a href="https://workspaced.online/terms" target="_blank" rel="noopener">Terms of service</a> and the
        <a href="https://workspaced.online/privacy" target="_blank" rel="noopener">Privacy policy</a>.
        We'll also email you a few tips now and then; you can turn them off at any time in Settings.</p>
    EOT
  }
}

resource "auth0_action" "signup_names" {
  name    = "Names from the sign-up form"
  runtime = "node22"
  deploy  = true

  supported_triggers {
    id      = "pre-user-registration"
    version = "v2"
  }

  code = <<-EOT
    const field = (body, name) => String(body?.[name] ?? "").trim().slice(0, 100);

    exports.onExecutePreUserRegistration = async (event, api) => {
      api.user.setUserMetadata("given_name", field(event.request.body, "ulp-given-name"));
      api.user.setUserMetadata("family_name", field(event.request.body, "ulp-family-name"));
    };
  EOT
}

resource "auth0_trigger_actions" "pre_user_registration" {
  trigger = "pre-user-registration"

  actions {
    id           = auth0_action.signup_names.id
    display_name = auth0_action.signup_names.name
  }
}

# The API reads profiles, saves name changes, and looks up recipe authors' names as the same
# application users sign in with, so it holds no second credential.
resource "auth0_client_grant" "workspaced_ai_users" {
  client_id = auth0_client.workspaced_ai.id
  audience  = "https://workspaced.eu.auth0.com/api/v2/"
  scopes    = ["read:users", "update:users"]
}
