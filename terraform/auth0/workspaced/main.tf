resource "auth0_tenant" "this" {
  friendly_name   = "Workspaced"
  support_email   = "support@workspaced.online"
  support_url     = "https://workspaced.online"
  enabled_locales = ["en"]

  # Links in verification and reset mail would otherwise point at the tenant's own domain.
  flags {
    enable_custom_domain_in_emails = true
  }

  depends_on = [auth0_custom_domain_verification.this]
}

import {
  to = auth0_connection.users
  id = "con_zt7Ccmf0dljwW2s1"
}

# Deleting the connection deletes every account in it. Signups stay off until registration
# opens, so until then each account is created by an admin.
resource "auth0_connection" "users" {
  name     = "Username-Password-Authentication"
  strategy = "auth0"

  options {
    password_policy        = "good"
    brute_force_protection = true
    disable_signup         = true
    requires_username      = false

    # History, dictionary and personal-info checks need a paid plan; breached-password
    # detection in attack-protection.tf covers the common case on the free one.
    password_complexity_options {
      min_length = 12
    }

    mfa {
      active                 = true
      return_enroll_settings = true
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Auth0 enables every new client on the connection by itself, so the list already exists.
import {
  to = auth0_connection_clients.users
  id = "con_zt7Ccmf0dljwW2s1"
}

resource "auth0_connection_clients" "users" {
  connection_id   = auth0_connection.users.id
  enabled_clients = [auth0_client.workspaced_ai.id]
}

# The API runs the authorization-code flow itself and then sets its own session cookie, so
# no Auth0 token ever reaches the browser. Its secret goes into secret/workspaced-secrets.
resource "auth0_client" "workspaced_ai" {
  name            = "workspaced-ai"
  app_type        = "regular_web"
  is_first_party  = true
  oidc_conformant = true
  grant_types     = ["authorization_code"]

  # localhost is the Vite dev server, which proxies /api to the API on 8080.
  callbacks = [
    "https://ai.workspaced.online/api/v1/login/oauth2/code/auth0",
    "http://localhost:5173/api/v1/login/oauth2/code/auth0",
  ]
  allowed_logout_urls = [
    "https://ai.workspaced.online/",
    "http://localhost:5173/",
  ]
  initiate_login_uri = "https://ai.workspaced.online/api/v1/oauth2/authorization/auth0"

  jwt_configuration {
    alg = "RS256"
  }
}

# client_secret_basic is what Spring Security's OAuth2 client sends by default.
resource "auth0_client_credentials" "workspaced_ai" {
  client_id             = auth0_client.workspaced_ai.id
  authentication_method = "client_secret_basic"
}
