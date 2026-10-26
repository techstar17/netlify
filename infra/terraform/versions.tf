terraform {
  required_version = ">= 1.10, < 2.0"
  backend "s3" {
    key          = "frame/production/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = "frame", Environment = "production", ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# CloudFront's global metrics are published only in us-east-1, even when
# the S3 origin is hosted in a different supported commercial region.
provider "aws" {
  alias  = "global"
  region = "us-east-1"
  default_tags {
    tags = { Project = "frame", Environment = "production", ManagedBy = "terraform" }
  }
}
