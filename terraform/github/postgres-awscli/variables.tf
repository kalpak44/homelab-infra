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
  description = "DeepSeek model the monthly release agent runs against"
  type        = string
  default     = "deepseek-v4-flash"
}