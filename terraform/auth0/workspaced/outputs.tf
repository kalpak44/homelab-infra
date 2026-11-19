output "client_id" {
  value = auth0_client.workspaced_ai.client_id
}

# Goes into secret/workspaced-secrets as auth0-client-secret.
output "client_secret" {
  value     = auth0_client_credentials.workspaced_ai.client_secret
  sensitive = true
}

output "dev_client_id" {
  value = auth0_client.workspaced_ai_dev.client_id
}

# Goes into secret/workspaced-dev-secrets as auth0-client-secret, which local development reads.
output "dev_client_secret" {
  value     = auth0_client_credentials.workspaced_ai_dev.client_secret
  sensitive = true
}
