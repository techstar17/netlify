locals {
  prefix = "frame-${data.aws_caller_identity.current.account_id}"
}
resource "aws_s3_bucket" "site" {
  bucket        = "${local.prefix}-production"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    id     = "expire-replaced-object-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
  depends_on = [aws_s3_bucket_versioning.site]
}

# Legacy CloudFront standard access logs require ACL-enabled ownership on this
# dedicated log bucket. The content bucket remains ACL-disabled and private.
data "aws_canonical_user_id" "current" {}
data "aws_cloudfront_log_delivery_canonical_user_id" "cloudfront" {}
resource "aws_s3_bucket" "logs" {
  bucket        = "${local.prefix}-access-logs"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule { object_ownership = "BucketOwnerPreferred" }
}
resource "aws_s3_bucket_acl" "logs" {
  bucket = aws_s3_bucket.logs.id
  access_control_policy {
    owner { id = data.aws_canonical_user_id.current.id }
    grant {
      grantee {
        id   = data.aws_canonical_user_id.current.id
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }
    grant {
      grantee {
        id   = data.aws_cloudfront_log_delivery_canonical_user_id.cloudfront.id
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }
  }
  depends_on = [aws_s3_bucket_ownership_controls.logs]
}
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "expire-access-logs"
    status = "Enabled"
    filter {}
    expiration { days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*"
      Resource  = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudFrontReadOnly", Effect = "Allow", Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject", Resource = "${aws_s3_bucket.site.arn}/*"
        Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.site.arn } }
      },
      {
        Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*"
        Resource  = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}
