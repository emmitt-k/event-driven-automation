# S3 Outputs
output "raw_files_bucket_name" {
  description = "Name of the S3 bucket for raw file uploads"
  value       = aws_s3_bucket.raw_files.bucket
}

output "processed_files_bucket_name" {
  description = "Name of the S3 bucket for processed files"
  value       = aws_s3_bucket.processed_files.bucket
}

# DynamoDB Outputs
output "metadata_table_name" {
  description = "Name of the DynamoDB table for file metadata"
  value       = aws_dynamodb_table.metadata.name
}

output "processing_status_table_name" {
  description = "Name of the DynamoDB table for processing status"
  value       = aws_dynamodb_table.processing_status.name
}

# OpenSearch Outputs
output "opensearch_collection_endpoint" {
  description = "Endpoint of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.collection.collection_endpoint
}

output "opensearch_collection_id" {
  description = "ID of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.collection.id
}

# Lambda Outputs
output "ingest_lambda_function_name" {
  description = "Name of the ingestion Lambda function"
  value       = aws_lambda_function.ingest.function_name
}

output "ingest_lambda_function_arn" {
  description = "ARN of the ingestion Lambda function"
  value       = aws_lambda_function.ingest.arn
}

output "query_lambda_function_name" {
  description = "Name of the query Lambda function"
  value       = aws_lambda_function.query.function_name
}

output "query_lambda_function_arn" {
  description = "ARN of the query Lambda function"
  value       = aws_lambda_function.query.arn
}

# API Gateway Outputs
output "api_gateway_invoke_url" {
  description = "Invoke URL for the API Gateway"
  value       = aws_api_gateway_stage.api_stage.invoke_url
}

output "api_gateway_rest_api_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.api.id
}

# SQS Outputs
output "processing_queue_url" {
  description = "URL of the SQS queue for file processing"
  value       = aws_sqs_queue.processing_queue.id
}

output "processing_queue_arn" {
  description = "ARN of the SQS queue for file processing"
  value       = aws_sqs_queue.processing_queue.arn
}

# EventBridge Outputs
output "event_bus_name" {
  description = "Name of the EventBridge event bus"
  value       = aws_cloudwatch_event_bus.event_bus.name
  sensitive   = true
}

# IAM Outputs
output "ingest_lambda_role_arn" {
  description = "ARN of the ingestion Lambda execution role"
  value       = aws_iam_role.ingest_lambda_role.arn
}

output "query_lambda_role_arn" {
  description = "ARN of the query Lambda execution role"
  value       = aws_iam_role.query_lambda_role.arn
}

# KMS Outputs
output "kms_key_id" {
  description = "ID of the KMS key for encryption"
  value       = aws_kms_key.encryption_key.key_id
  sensitive   = true
}

output "kms_key_arn" {
  description = "ARN of the KMS key for encryption"
  value       = aws_kms_key.encryption_key.arn
  sensitive   = true
}

# Combined Outputs
output "project_info" {
  description = "Combined project information"
  value = {
    project_name = var.project_name
    environment  = var.environment
    aws_region   = var.aws_region
    account_id   = data.aws_caller_identity.current.account_id
  }
}