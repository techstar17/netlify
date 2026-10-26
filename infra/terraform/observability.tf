resource "aws_sns_topic" "alerts" {
  provider = aws.global
  name     = "frame-production-alerts"
}
resource "aws_sns_topic_subscription" "email" {
  provider  = aws.global
  count     = var.alert_email == null ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
resource "aws_sns_topic_policy" "alerts" {
  provider = aws.global
  arn      = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Principal = { Service = "cloudwatch.amazonaws.com" }, Action = "SNS:Publish", Resource = aws_sns_topic.alerts.arn
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:cloudwatch:us-east-1:${data.aws_caller_identity.current.account_id}:alarm:frame-*" }
      }
    }]
  })
}
resource "aws_cloudwatch_metric_alarm" "server_errors" {
  provider            = aws.global
  alarm_name          = "frame-cloudfront-server-errors"
  alarm_description   = "5xx rate above 1% for two five-minute periods. Inspect CloudFront access logs and roll back a bad release."
  namespace           = "AWS/CloudFront"
  metric_name         = "5xxErrorRate"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { DistributionId = aws_cloudfront_distribution.site.id, Region = "Global" }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
resource "aws_cloudwatch_metric_alarm" "client_errors" {
  provider            = aws.global
  alarm_name          = "frame-cloudfront-client-errors"
  alarm_description   = "4xx rate above 5% for two five-minute periods; investigate missing release assets and S3 permissions."
  namespace           = "AWS/CloudFront"
  metric_name         = "4xxErrorRate"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { DistributionId = aws_cloudfront_distribution.site.id, Region = "Global" }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
resource "aws_cloudwatch_dashboard" "site" {
  provider       = aws.global
  dashboard_name = "FRAME-production"
  dashboard_body = jsonencode({ widgets = [
    for index, metric in ["Requests", "4xxErrorRate", "5xxErrorRate", "BytesDownloaded"] : {
      type = "metric", x = (index % 2) * 12, y = floor(index / 2) * 6, width = 12, height = 6
      properties = {
        title   = metric, region = "us-east-1", period = 300, stat = contains(["Requests", "BytesDownloaded"], metric) ? "Sum" : "Average"
        metrics = [["AWS/CloudFront", metric, "DistributionId", aws_cloudfront_distribution.site.id, "Region", "Global"]]
      }
    }
  ] })
}
resource "aws_budgets_budget" "project" {
  provider     = aws.global
  name         = "frame-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$frame"]
  }
  dynamic "notification" {
    for_each = var.alert_email == null ? [] : [80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }
}
