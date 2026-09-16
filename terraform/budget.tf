# Emails the moment actual spend crosses $10 — half the $15 total budget for the whole project.
resource "aws_budgets_budget" "ghosthref" {
  name         = "ghosthref-monthly"
  budget_type  = "COST"
  limit_amount = "10"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
