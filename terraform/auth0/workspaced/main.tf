resource "auth0_tenant" "this" {
  friendly_name   = "workspaced"
  support_email   = "support@workspaced.online"
  support_url     = "https://workspaced.online"
  enabled_locales = ["en"]

  # Where Auth0's own pages, such as "email verified", send the user back: straight into signing
  # in to the app. A per-template result_url would say the same, but needs an Enterprise plan.
  default_redirection_uri = "https://ai.workspaced.online/api/v1/oauth2/authorization/auth0"

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

# Deleting the connection deletes every account in it. Anyone may sign up; the app refuses an
# address that is not verified yet, so a new account first confirms its email.
resource "auth0_connection" "users" {
  name     = "Username-Password-Authentication"
  strategy = "auth0"

  options {
    password_policy        = "good"
    brute_force_protection = true
    disable_signup         = false
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
  enabled_clients = [auth0_client.workspaced_ai.id, auth0_client.workspaced_ai_dev.id]
}

# The API runs the authorization-code flow itself and then sets its own session cookie, so
# no Auth0 token ever reaches the browser. Its secret goes into secret/workspaced-secrets.
resource "auth0_client" "workspaced_ai" {
  name            = "workspaced-ai"
  app_type        = "regular_web"
  is_first_party  = true
  oidc_conformant = true
  grant_types     = ["authorization_code", "client_credentials"]

  callbacks = ["https://ai.workspaced.online/api/v1/login/oauth2/code/auth0"]
  # Signing out ends on the public site; an unverified sign-up ends on the app's page that
  # explains it.
  allowed_logout_urls = [
    "https://workspaced.online/",
    "https://ai.workspaced.online/verify-email",
  ]
  initiate_login_uri = "https://ai.workspaced.online/api/v1/oauth2/authorization/auth0"

  jwt_configuration {
    alg = "RS256"
  }
}

# Local development signs in as this application, never the production one: it has no Management
# API grant, so a leaked secret from a laptop cannot read or change any user. localhost is the
# Vite dev server, which proxies /api to the API on 8080.
resource "auth0_client" "workspaced_ai_dev" {
  name            = "workspaced-ai-dev"
  app_type        = "regular_web"
  is_first_party  = true
  oidc_conformant = true
  grant_types     = ["authorization_code"]

  callbacks = ["http://localhost:5173/api/v1/login/oauth2/code/auth0"]
  allowed_logout_urls = [
    "http://localhost:5173/",
    "http://localhost:5173/verify-email",
  ]

  jwt_configuration {
    alg = "RS256"
  }
}

resource "auth0_client_credentials" "workspaced_ai_dev" {
  client_id             = auth0_client.workspaced_ai_dev.id
  authentication_method = "client_secret_basic"
}

# client_secret_basic is what Spring Security's OAuth2 client sends by default.
resource "auth0_client_credentials" "workspaced_ai" {
  client_id             = auth0_client.workspaced_ai.id
  authentication_method = "client_secret_basic"
}
