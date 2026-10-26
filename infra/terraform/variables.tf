variable "aws_region" {
  description = "Region for the S3 origin and access logs. CloudFront metrics, alerts, and budget operations use us-east-1."
  type        = string
  default     = "us-east-1"
  validation {
    condition     = can(regex("^(us|eu|ap|ca|sa|af|me|il|mx)-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "Use a commercial AWS region identifier, such as us-east-1 or us-east-2."
  }
}
variable "github_repository" {
  description = "Only this repository's production GitHub environment can assume the deploy role."
  type        = string
  default     = "techstar17/netlify"
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use owner/repository without wildcards."
  }
}
variable "github_environment" {
  type    = string
  default = "production"
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", var.github_environment))
    error_message = "Use a nonempty GitHub environment name without wildcards."
  }
}
variable "create_github_oidc_provider" {
  description = "Set false when token.actions.githubusercontent.com is already registered in the AWS account."
  type        = bool
  default     = true
}
variable "alert_email" {
  description = "Optional email for SNS and budget alerts; SNS subscription requires confirmation."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.alert_email == null ? true : can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.alert_email))
    error_message = "Provide a valid email or null."
  }
}
variable "monthly_budget_usd" {
  description = "Project cost notification threshold, not a spending cap. Enable the Project cost allocation tag in Billing."
  type        = number
  default     = 10
  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "Budget must be greater than zero."
  }
}
variable "custom_domain" {
  description = "Optional existing hostname. Set with a matching, validated ACM certificate in us-east-1; manage DNS separately."
  type        = string
  default     = null
  validation {
    condition     = var.custom_domain == null ? true : can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.custom_domain))
    error_message = "Provide a hostname without scheme or path."
  }
}
variable "acm_certificate_arn" {
  description = "Optional existing ACM certificate in us-east-1, required when custom_domain is set."
  type        = string
  default     = null
  validation {
    condition     = var.acm_certificate_arn == null ? true : can(regex("^arn:aws:acm:us-east-1:[0-9]{12}:certificate/", var.acm_certificate_arn))
    error_message = "CloudFront requires an ACM certificate ARN from us-east-1."
  }
}
