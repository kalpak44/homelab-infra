# Applied only with the aws-admin SSO session (`just deploy-aws-admin personal`), so the
# key below can never widen its own permissions.

resource "aws_iam_user" "terraform" {
  name = "homelab-infra-terraform"
}

# Grant only what the workload concerns manage; a leaked key can then edit one budget
# alert and nothing else.
resource "aws_iam_user_policy" "budgets" {
  name = "monthly-cost-budget"
  user = aws_iam_user.terraform.name

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

# Rotate with `-replace=aws_iam_access_key.terraform`, then update .env and Vault:
# the workload concerns read the key from AWS_TERRAFORM_ACCESS_KEY_ID/_SECRET_ACCESS_KEY.
resource "aws_iam_access_key" "terraform" {
  user = aws_iam_user.terraform.name
}

output "terraform_access_key_id" {
  value = aws_iam_access_key.terraform.id
}

output "terraform_secret_access_key" {
  value     = aws_iam_access_key.terraform.secret
  sensitive = true
}
