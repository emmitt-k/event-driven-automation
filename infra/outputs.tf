output "raw_input_bucket" {
  description = "Name of the S3 bucket for raw input files"
  value       = aws_s3_bucket.raw_input.bucket
}

output "processed_output_bucket" {
  description = "Name of the S3 bucket for processed output files"
  value       = aws_s3_bucket.processed_output.bucket
}

output "api_endpoint" {
  description = "HTTP API Gateway endpoint URL"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "opensearch_collection_endpoint" {
  description = "OpenSearch Serverless Collection Endpoint"
  value       = aws_opensearchserverless_collection.vector_store.collection_endpoint
}
