terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
  backend "s3" {
    # Configuration will be set via environment variables or CLI flags
    # terraform init -backend-config="bucket=terraform-state-<account-id>"
    # -backend-config="key=event-driven-automation/terraform.tfstate"
    # -backend-config="region=us-east-1"
    # -backend-config="encrypt=true"
    # -backend-config="dynamodb_table=terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "event-driven-automation"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Data sources for getting current account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for consistent naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}