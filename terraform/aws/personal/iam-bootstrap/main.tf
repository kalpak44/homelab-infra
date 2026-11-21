data "aws_iam_roles" "local_admin" {
  name_regex  = "^AWSReservedSSO_AdministratorAccess_"
  path_prefix = "/aws-reserved/sso.amazonaws.com/eu-central-1/"
}

resource "aws_iam_role" "terraform" {
  name                 = "homelab-infra-terraform"
  description          = "Local Terraform access through the account administrator SSO role"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = one(data.aws_iam_roles.local_admin.arns)
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "budgets" {
  name = "monthly-cost-budget"
  role = aws_iam_role.terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "budgets:ViewBudget",
        "budgets:ModifyBudget",
        "budgets:ListTagsForResource",
      ]
      Resource = "arn:aws:budgets::039959484327:budget/personal-monthly-20-usd"
    }]
  })
}

output "terraform_role_arn" {
  value = aws_iam_role.terraform.arn
}
