# MFA is optional: the policy challenges no one, and the action below asks only users who
# have enrolled, or whose sign-in asked to enroll.
resource "auth0_guardian" "this" {
  policy        = "never"
  otp           = true
  recovery_code = true
}

resource "auth0_action" "mfa" {
  name    = "Optional MFA"
  runtime = "node22"
  deploy  = true

  supported_triggers {
    id      = "post-login"
    version = "v3"
  }

  # The app asks to enroll by sending this acr_values on the authorization request.
  code = <<-EOT
    const MFA = "http://schemas.openid.net/pape/policies/2007/06/multi-factor";

    exports.onExecutePostLogin = async (event, api) => {
      const enrolled = (event.user.multifactor || []).length > 0;
      const requested = (event.transaction?.acr_values || []).includes(MFA);
      if (enrolled || requested) {
        api.multifactor.enable("any", { allowRememberBrowser: false });
      }
    };
  EOT
}

resource "auth0_trigger_actions" "post_login" {
  trigger = "post-login"

  actions {
    id           = auth0_action.mfa.id
    display_name = auth0_action.mfa.name
  }

  actions {
    id           = auth0_action.roles.id
    display_name = auth0_action.roles.name
  }
}
