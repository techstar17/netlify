resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${local.prefix}-s3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "aws_cloudfront_cache_policy" "site" {
  name        = "${local.prefix}-cache-control"
  min_ttl     = 0
  default_ttl = 86400
  max_ttl     = 31536000
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}
resource "aws_cloudfront_response_headers_policy" "security" {
  name = "${local.prefix}-security"
  security_headers_config {
    content_security_policy {
      content_security_policy = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; media-src 'self'; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; upgrade-insecure-requests"
      override                = true
    }
    content_type_options { override = true }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = false
      override                   = true
    }
    xss_protection {
      protection = true
      mode_block = true
      override   = true
    }
  }
  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=()"
      override = true
    }
  }
}
resource "aws_cloudfront_distribution" "site" {
  aliases             = var.custom_domain == null ? [] : [var.custom_domain]
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "FRAME production"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  http_version        = "http2and3"
  wait_for_deployment = true
  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "private-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }
  default_cache_behavior {
    target_origin_id           = "private-s3"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.site.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate {
    cloudfront_default_certificate = var.custom_domain == null
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.custom_domain == null ? null : "sni-only"
    minimum_protocol_version       = var.custom_domain == null ? "TLSv1" : "TLSv1.2_2021"
  }
  logging_config {
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    prefix          = "cloudfront/"
    include_cookies = false
  }
  lifecycle {
    precondition {
      condition     = (var.custom_domain == null) == (var.acm_certificate_arn == null)
      error_message = "custom_domain and acm_certificate_arn must be set together."
    }
  }
  depends_on = [aws_s3_bucket_acl.logs]
}
