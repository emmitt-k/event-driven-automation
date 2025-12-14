variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "event-driven-automation"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# S3 Variables
variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket names"
  type        = string
  default     = "eda"
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

# DynamoDB Variables
variable "dynamodb_table_prefix" {
  description = "Prefix for DynamoDB table names"
  type        = string
  default     = "eda"
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
}

# Lambda Variables
variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.11"
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
}

# API Gateway Variables
variable "api_gateway_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "api"
}

variable "enable_api_gateway_logging" {
  description = "Enable API Gateway logging"
  type        = bool
  default     = true
}

# OpenSearch Variables
variable "opensearch_collection_name" {
  description = "OpenSearch Serverless collection name"
  type        = string
  default     = "eda-vector-index"
}

variable "opensearch_dimension" {
  description = "Vector dimension for OpenSearch embeddings"
  type        = number
  default     = 1536
}

# Bedrock Variables
variable "bedrock_model_id" {
  description = "Bedrock model ID for text extraction"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
}

variable "bedrock_embedding_model_id" {
  description = "Bedrock embedding model ID"
  type        = string
  default     = "amazon.titan-embed-text-v1"
}

# Security Variables
variable "enable_encryption" {
  description = "Enable encryption for supported services"
  type        = bool
  default     = true
}

variable "kms_key_alias" {
  description = "KMS key alias for encryption"
  type        = string
  default     = "alias/eda-encryption-key"
}