# Staging Environment Configuration
project_name = "event-driven-automation"
environment  = "staging"
aws_region   = "us-east-1"

# Staging-specific settings
s3_bucket_prefix    = "eda-staging"
enable_s3_versioning = true

dynamodb_table_prefix = "eda-staging"
dynamodb_billing_mode = "PAY_PER_REQUEST"

lambda_runtime    = "python3.11"
lambda_memory_size = 512  # Production-like sizing
lambda_timeout    = 300  # 5 minutes

api_gateway_stage_name = "staging"
enable_api_gateway_logging = true

opensearch_collection_name = "eda-staging-vector-index"
opensearch_dimension = 1536

bedrock_model_id = "anthropic.claude-3-sonnet-20240229-v1:0"
bedrock_embedding_model_id = "amazon.titan-embed-text-v1"

enable_encryption = true
kms_key_alias = "alias/eda-staging-encryption-key"

tags = {
  Owner       = "staging-team@yourcompany.com"
  CostCenter  = "engineering"
  Environment = "staging"
  Project     = "event-driven-automation"
}