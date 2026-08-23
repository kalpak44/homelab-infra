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
  description = "SonarCloud project key the agent queries for issues and the quality gate"
  type        = string
  default     = "bunker-party"
}

variable "sonar_organization" {
  description = "SonarCloud organization owning the project"
  type        = string
  default     = "kalpak44"
}