# Development Environment Configuration
project_name = "event-driven-automation"
environment  = "dev"
aws_region   = "us-east-1"

# Development-specific settings
s3_bucket_prefix    = "eda-dev"
enable_s3_versioning = true

dynamodb_table_prefix = "eda-dev"
dynamodb_billing_mode = "PAY_PER_REQUEST"

lambda_runtime    = "python3.11"
lambda_memory_size = 256  # Smaller for dev
lambda_timeout    = 180  # 3 minutes

api_gateway_stage_name = "dev"
enable_api_gateway_logging = false  # Reduce costs in dev

opensearch_collection_name = "eda-dev-vector-index"
opensearch_dimension = 1536

bedrock_model_id = "anthropic.claude-3-sonnet-20240229-v1:0"
bedrock_embedding_model_id = "amazon.titan-embed-text-v1"

enable_encryption = true
kms_key_alias = "alias/eda-dev-encryption-key"

tags = {
  Owner       = "development-team@yourcompany.com"
  CostCenter  = "engineering"
  Environment = "development"
  Project     = "event-driven-automation"
}