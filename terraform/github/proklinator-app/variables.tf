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
    GitHub logins whose pull requests ai-pr-review.yml may review, run and merge.
    The reviewer executes the PR's code with a write token, so this is a trust list,
    not a notification list. An empty list disables the reviewer entirely.
  EOT
  type        = list(string)
  default     = ["kalpak44"]
}

variable "ai_max_review_rounds" {
  description = <<-EOT
    How many times the reviewer may send an agent-authored PR back to the implementer
    before the loop stops and the issue is marked ai:blocked for a human. Each round is a
    full model run plus a browser QA pass on both sides, so this is a spend cap as much as
    a correctness one.
  EOT
  type        = number
  default     = 3

  validation {
    condition     = var.ai_max_review_rounds >= 1 && var.ai_max_review_rounds <= 10
    error_message = "ai_max_review_rounds must be between 1 and 10 — an uncapped loop is not an option."
  }
}
