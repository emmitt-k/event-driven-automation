# Production Environment Configuration
project_name = "event-driven-automation"
environment  = "prod"
aws_region   = "us-east-1"

# Production-specific settings
s3_bucket_prefix    = "eda-prod"
enable_s3_versioning = true

dynamodb_table_prefix = "eda-prod"
dynamodb_billing_mode = "PAY_PER_REQUEST"

lambda_runtime    = "python3.11"
lambda_memory_size = 1024  # Larger for production workloads
lambda_timeout    = 900  # 15 minutes (max)

api_gateway_stage_name = "v1"
enable_api_gateway_logging = true

opensearch_collection_name = "eda-prod-vector-index"
opensearch_dimension = 1536

bedrock_model_id = "anthropic.claude-3-sonnet-20240229-v1:0"
bedrock_embedding_model_id = "amazon.titan-embed-text-v1"

enable_encryption = true
kms_key_alias = "alias/eda-prod-encryption-key"

tags = {
  Owner       = "platform-team@yourcompany.com"
  CostCenter  = "platform"
  Environment = "production"
  Project     = "event-driven-automation"
  Compliance  = "sox"
  DataClassification = "confidential"
}