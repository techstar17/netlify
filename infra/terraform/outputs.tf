output "site_url" { value = "https://${var.custom_domain == null ? aws_cloudfront_distribution.site.domain_name : var.custom_domain}" }
output "site_bucket" { value = aws_s3_bucket.site.id }
output "distribution_id" { value = aws_cloudfront_distribution.site.id }
output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
output "access_logs_bucket" { value = aws_s3_bucket.logs.id }
output "dashboard_name" { value = aws_cloudwatch_dashboard.site.dashboard_name }

output "aws_region" { value = var.aws_region }
