resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
locals {
  github_oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}
resource "aws_iam_role" "deploy" {
  name                 = "frame-production-deploy"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Principal = { Federated = local.github_oidc_arn }, Action = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:${var.github_environment}"
      } }
    }]
  })
}
resource "aws_iam_role_policy" "deploy" {
  name = "release-publishing"
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.site.arn },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = ["${aws_s3_bucket.site.arn}/releases/*", "${aws_s3_bucket.site.arn}/index.html"] },
      { Effect = "Allow", Action = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation", "cloudfront:GetDistribution"], Resource = aws_cloudfront_distribution.site.arn }
    ]
  })
}
