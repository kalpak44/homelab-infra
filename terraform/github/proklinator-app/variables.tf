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

variable "pr_review_allowlist" {
  description = <<-EOT
    GitHub logins whose `ai:ready` label starts the resolver. It runs model-written code
    with a write token and merges what comes out, so this is a trust list, not a
    notification list. An empty list disables the loop entirely.
  EOT
  type        = list(string)
  default     = ["kalpak44"]
}

variable "ai_max_fix_rounds" {
  description = <<-EOT
    How many failed check runs the resolver may try to repair before it stops and marks
    the issue ai:blocked for a human. Each round is a full model run plus a browser QA
    pass, so this is a spend cap as much as a correctness one.
  EOT
  type        = number
  default     = 3

  validation {
    condition     = var.ai_max_fix_rounds >= 1 && var.ai_max_fix_rounds <= 10
    error_message = "ai_max_fix_rounds must be between 1 and 10 — an uncapped loop is not an option."
  }
}

variable "sonar_organization" {
  description = "SonarCloud organization owning both projects"
  type        = string
  default     = "kalpak44"
}

variable "sonar_project_key_site" {
  description = "SonarCloud project key publish.yml analyses src/ against"
  type        = string
  default     = "proklinator-app"
}

variable "sonar_project_key_api" {
  description = "SonarCloud project key publish.yml analyses backend/src/ against"
  type        = string
  default     = "proklinator-app-api"
}

variable "sonar_token" {
  description = "SonarCloud token, published to both secret stores so the quality gates also run on Dependabot PRs"
  type        = string
  sensitive   = true
  default     = ""
}
