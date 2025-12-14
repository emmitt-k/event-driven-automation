# Lambda function packages
data "archive_file" "ingest_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/src/ingest_worker"
  output_path = "${path.module}/tmp/ingest_lambda.zip"
}

data "archive_file" "query_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/src/query_api"
  output_path = "${path.module}/tmp/query_lambda.zip"
}

# IAM Roles for Lambda functions
resource "aws_iam_role" "ingest_lambda_role" {
  name = "${local.name_prefix}-ingest-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ingest-lambda-role"
    Type = "IAMRole"
  })
}

resource "aws_iam_role" "query_lambda_role" {
  name = "${local.name_prefix}-query-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-query-lambda-role"
    Type = "IAMRole"
  })
}

# IAM Policies for Lambda functions
resource "aws_iam_role_policy_attachment" "ingest_lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.ingest_lambda_role.name
}

resource "aws_iam_role_policy_attachment" "query_lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.query_lambda_role.name
}

resource "aws_iam_role_policy" "ingest_lambda_policy" {
  name = "${local.name_prefix}-ingest-lambda-policy"
  role = aws_iam_role.ingest_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.raw_files.arn}/*",
          "${aws_s3_bucket.processed_files.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.metadata.arn,
          "${aws_dynamodb_table.metadata.arn}/*",
          aws_dynamodb_table.processing_status.arn,
          "${aws_dynamodb_table.processing_status.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_model_id}",
          "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_embedding_model_id}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = var.enable_encryption ? [aws_kms_key.encryption_key.arn] : []
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "query_lambda_policy" {
  name = "${local.name_prefix}-query-lambda-policy"
  role = aws_iam_role.query_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.metadata.arn,
          "${aws_dynamodb_table.metadata.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = var.enable_encryption ? [aws_kms_key.encryption_key.arn] : []
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# Lambda Functions
resource "aws_lambda_function" "ingest" {
  function_name    = "${local.name_prefix}-ingest"
  runtime          = var.lambda_runtime
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.ingest_lambda_role.arn
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout

  filename         = data.archive_file.ingest_lambda_zip.output_path
  source_code_hash = data.archive_file.ingest_lambda_zip.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT           = var.environment
      RAW_FILES_BUCKET      = aws_s3_bucket.raw_files.bucket
      PROCESSED_FILES_BUCKET = aws_s3_bucket.processed_files.bucket
      METADATA_TABLE        = aws_dynamodb_table.metadata.name
      PROCESSING_STATUS_TABLE = aws_dynamodb_table.processing_status.name
      OPENSEARCH_ENDPOINT  = aws_opensearchserverless_collection.collection.collection_endpoint
      OPENSEARCH_INDEX     = "documents"
      BEDROCK_MODEL_ID     = var.bedrock_model_id
      BEDROCK_EMBEDDING_MODEL_ID = var.bedrock_embedding_model_id
      KMS_KEY_ARN          = var.enable_encryption ? aws_kms_key.encryption_key.arn : ""
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ingest"
    Type = "LambdaFunction"
  })
}

resource "aws_lambda_function" "query" {
  function_name    = "${local.name_prefix}-query"
  runtime          = var.lambda_runtime
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.query_lambda_role.arn
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout

  filename         = data.archive_file.query_lambda_zip.output_path
  source_code_hash = data.archive_file.query_lambda_zip.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT          = var.environment
      METADATA_TABLE      = aws_dynamodb_table.metadata.name
      OPENSEARCH_ENDPOINT = aws_opensearchserverless_collection.collection.collection_endpoint
      OPENSEARCH_INDEX    = "documents"
      KMS_KEY_ARN         = var.enable_encryption ? aws_kms_key.encryption_key.arn : ""
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-query"
    Type = "LambdaFunction"
  })
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "ingest_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.ingest.function_name}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ingest-logs"
    Type = "LogGroup"
  })
}

resource "aws_cloudwatch_log_group" "query_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.query.function_name}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-query-logs"
    Type = "LogGroup"
  })
}