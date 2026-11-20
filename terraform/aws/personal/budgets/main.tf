resource "aws_budgets_budget" "monthly" {
  account_id   = "039959484327"
  name         = "personal-monthly-20-usd"
  budget_type  = "COST"
  limit_amount = "20"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Include taxes and subscriptions, with credits/refunds reducing the payable total.
  cost_types {
    include_credit             = true
    include_discount           = true
    include_other_subscription = true
    include_recurring          = true
    include_refund             = true
    include_subscription       = true
    include_support            = true
    include_tax                = true
    include_upfront            = true
    use_amortized              = false
    use_blended                = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 20
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["pavel.usanli@gmail.com"]
  }
}

output "budget_name" {
  value = aws_budgets_budget.monthly.name
}
