mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:123456789012:frame-production-alerts" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn                         = "arn:aws:s3:::frame-test-bucket"
      id                          = "frame-test-bucket"
      bucket_domain_name          = "frame-test-bucket.s3.amazonaws.com"
      bucket_regional_domain_name = "frame-test-bucket.s3.us-east-1.amazonaws.com"
    }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn         = "arn:aws:cloudfront::123456789012:distribution/ETEST123456"
      id          = "ETEST123456"
      domain_name = "dtest123.cloudfront.net"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test"
      user_id    = "test"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition          = "aws"
      dns_suffix         = "amazonaws.com"
      reverse_dns_prefix = "com.amazonaws"
    }
  }
}

mock_provider "aws" {
  alias = "global"
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:123456789012:frame-production-alerts" }
  }
}

run "private_origin_and_restricted_identity" {
  command = apply
  assert {
    condition     = aws_s3_bucket_public_access_block.site.block_public_policy && aws_s3_bucket_public_access_block.site.block_public_acls && aws_s3_bucket_public_access_block.site.ignore_public_acls && aws_s3_bucket_public_access_block.site.restrict_public_buckets
    error_message = "The content bucket must block all public access."
  }
  assert {
    condition     = aws_s3_bucket_ownership_controls.site.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Application content must not use ACLs."
  }
  assert {
    condition     = aws_s3_bucket_versioning.site.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning is required for entry-point recovery."
  }
  assert {
    condition     = aws_cloudfront_origin_access_control.site.signing_behavior == "always" && aws_cloudfront_origin_access_control.site.signing_protocol == "sigv4"
    error_message = "Origin requests must be signed."
  }
  assert {
    condition     = aws_cloudfront_distribution.site.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "Viewer requests must use HTTPS."
  }
  assert {
    condition     = aws_cloudfront_cache_policy.site.min_ttl == 0
    error_message = "A minimum TTL above zero breaks atomic entry-point switching."
  }
  assert {
    condition     = jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:techstar17/netlify:environment:production"
    error_message = "OIDC trust must be restricted to this repository's production environment."
  }
  assert {
    condition     = jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "OIDC audience must be AWS STS."
  }
  assert {
    condition     = jsondecode(aws_s3_bucket_policy.site.policy).Statement[0].Condition.StringEquals["AWS:SourceArn"] == aws_cloudfront_distribution.site.arn && jsondecode(aws_s3_bucket_policy.site.policy).Statement[0].Principal.Service == "cloudfront.amazonaws.com"
    error_message = "Origin reads must be restricted to this CloudFront distribution."
  }
  assert {
    condition     = alltrue([for action in flatten([for statement in jsondecode(aws_iam_role_policy.deploy.policy).Statement : statement.Action]) : contains(["s3:ListBucket", "s3:GetObject", "s3:PutObject", "cloudfront:CreateInvalidation", "cloudfront:GetInvalidation", "cloudfront:GetDistribution"], action)])
    error_message = "The deploy role must not gain deletion or infrastructure administration permissions."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.server_errors.alarm_actions == toset([aws_sns_topic.alerts.arn])
    error_message = "Server-error alarm must publish notifications."
  }
  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "Do not invent an email recipient."
  }
}

run "existing_oidc_provider" {
  command = plan
  variables { create_github_oidc_provider = false }
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "An account's existing OIDC provider must be reused."
  }
}

run "custom_domain_tls_policy" {
  command = plan
  variables {
    custom_domain       = "frame.example.com"
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    alert_email         = "engineer@example.com"
  }
  assert {
    condition     = aws_cloudfront_distribution.site.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021" && !aws_cloudfront_distribution.site.viewer_certificate[0].cloudfront_default_certificate
    error_message = "Custom domain must use the modern TLS policy."
  }
  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1
    error_message = "Create the requested alert subscription."
  }
}

run "reject_half_configured_custom_domain" {
  command = plan
  variables { custom_domain = "frame.example.com" }
  expect_failures = [aws_cloudfront_distribution.site]
}

run "reject_invalid_region" {
  command = plan
  variables { aws_region = "not-a-region" }
  expect_failures = [var.aws_region]
}

run "regional_origin_with_global_monitoring" {
  command = plan
  variables { aws_region = "us-east-2" }
  assert {
    condition     = aws_cloudwatch_dashboard.site.dashboard_name == "FRAME-production" && jsondecode(aws_sns_topic_policy.alerts.policy).Statement[0].Condition.ArnLike["aws:SourceArn"] == "arn:aws:cloudwatch:us-east-1:123456789012:alarm:frame-*"
    error_message = "CloudFront monitoring must remain global when the S3 region changes."
  }
}
