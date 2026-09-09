variable "github_owner" {
  description = "GitHub user or org that owns the repository"
  type        = string
  default     = "kalpak44"
}

variable "github_token" {
  description = "GitHub PAT with repo + workflow scope (Administration, Contents, Secrets, Workflows: write)"
  type        = string
  sensitive   = true
}

variable "deepseek_api_key" {
  description = "DeepSeek API key, published to the repo as the DEEPSEEK_APIKEY secret"
  type        = string
  sensitive   = true
}

variable "deepseek_model" {
  description = "DeepSeek model the PR agent runs against"
  type        = string
  default     = "deepseek-v4-flash"
}

variable "sonar_project_key" {
  description = "SonarCloud project key publish.yml analyses against"
  type        = string
  default     = "mite-assistant-mcp"
}

variable "sonar_organization" {
  description = "SonarCloud organization owning the project"
  type        = string
  default     = "kalpak44"
}

variable "sonar_token" {
  description = "SonarCloud token, published to both secret stores so the quality gate also runs on Dependabot PRs"
  type        = string
  sensitive   = true
  default     = ""
}
