resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_roles" "local_admin" {
  name_regex  = "^AWSReservedSSO_AdministratorAccess_"
  path_prefix = "/aws-reserved/sso.amazonaws.com/eu-central-1/"
}

resource "aws_iam_role" "terraform" {
  name                 = "homelab-infra-terraform"
  description          = "GitHub Actions OIDC for kalpak44/homelab-infra main"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:kalpak44/homelab-infra:ref:refs/heads/main"
        }
      }
      }, {
      Effect = "Allow"
      Principal = {
        AWS = one(data.aws_iam_roles.local_admin.arns)
      }
      Action = "sts:AssumeRole"
    }]
  })

  # The current account concern needs only GetCallerIdentity, which requires no policy.
  # Add scoped resource permissions here when introducing further AWS concerns.
}

resource "github_actions_variable" "terraform_role" {
  repository    = "homelab-infra"
  variable_name = "AWS_TERRAFORM_ROLE_ARN"
  value         = aws_iam_role.terraform.arn
}

output "terraform_role_arn" {
  value = aws_iam_role.terraform.arn
}
