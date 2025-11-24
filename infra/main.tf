terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# --- S3 Buckets ---

resource "aws_s3_bucket" "raw_input" {
  bucket = "${var.project_name}-raw-input-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket" "processed_output" {
  bucket = "${var.project_name}-processed-output-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

# Enable EventBridge notifications for S3
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.raw_input.id
  eventbridge = true
}

# --- SQS Queue ---

resource "aws_sqs_queue" "dlq" {
  name = "${var.project_name}-ingestion-dlq"
}

resource "aws_sqs_queue" "ingestion_queue" {
  name = "${var.project_name}-ingestion-queue"
  visibility_timeout_seconds = 300 # Match Lambda timeout
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_policy" "ingestion_queue_policy" {
  queue_url = aws_sqs_queue.ingestion_queue.id
  policy    = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.ingestion_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.s3_upload.arn
          }
        }
      }
    ]
  })
}

# --- EventBridge Rule ---

resource "aws_cloudwatch_event_rule" "s3_upload" {
  name        = "${var.project_name}-s3-upload-rule"
  description = "Capture S3 object created events"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.raw_input.bucket]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "sqs_target" {
  rule      = aws_cloudwatch_event_rule.s3_upload.name
  target_id = "SendToSQS"
  arn       = aws_sqs_queue.ingestion_queue.arn
}

# --- DynamoDB ---

resource "aws_dynamodb_table" "documents" {
  name         = "${var.project_name}-documents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "docId"

  attribute {
    name = "docId"
    type = "S"
  }
}

# --- OpenSearch Serverless ---

resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "${var.project_name}-encryption"
  type        = "encryption"
  description = "Encryption policy for ${var.project_name}"
  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource = [
          "collection/${var.project_name}-vector-store"
        ]
      }
    ],
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name        = "${var.project_name}-network"
  type        = "network"
  description = "Network policy for ${var.project_name}"
  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource = [
            "collection/${var.project_name}-vector-store"
          ]
        },
        {
          ResourceType = "dashboard"
          Resource = [
            "collection/${var.project_name}-vector-store"
          ]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

resource "aws_opensearchserverless_collection" "vector_store" {
  name             = "${var.project_name}-vector-store"
  type             = "VECTORSEARCH"
  depends_on       = [aws_opensearchserverless_security_policy.encryption]
}

resource "aws_opensearchserverless_access_policy" "data_access" {
  name        = "${var.project_name}-access"
  type        = "data"
  description = "Access policy for ${var.project_name}"
  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource = [
            "collection/${var.project_name}-vector-store"
          ]
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:DeleteCollectionItems",
            "aoss:UpdateCollectionItems",
            "aoss:DescribeCollectionItems"
          ]
        },
        {
          ResourceType = "index"
          Resource = [
            "index/${var.project_name}-vector-store/*"
          ]
          Permission = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument"
          ]
        }
      ],
      Principal = [
        data.aws_caller_identity.current.arn,
        aws_iam_role.ingest_worker_role.arn,
        aws_iam_role.query_api_role.arn
      ]
    }
  ])
}

# --- Lambda: Ingest Worker ---

data "archive_file" "ingest_worker_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/ingest_worker"
  output_path = "${path.module}/ingest_worker.zip"
  excludes    = ["requirements.txt"] # We'll handle layers later if needed, or assume simple for now
}

resource "aws_iam_role" "ingest_worker_role" {
  name = "${var.project_name}-ingest-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ingest_worker_basic" {
  role       = aws_iam_role.ingest_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ingest_worker_policy" {
  name = "${var.project_name}-ingest-worker-policy"
  role = aws_iam_role.ingest_worker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.raw_input.arn}/*",
          "${aws_s3_bucket.processed_output.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.ingestion_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.documents.arn
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "*" # Scope down to specific models in prod
      },
      {
        Effect = "Allow"
        Action = [
           "aoss:APIAccessAll"
        ]
        Resource = aws_opensearchserverless_collection.vector_store.arn
      }
    ]
  })
}

resource "aws_lambda_function" "ingest_worker" {
  filename         = data.archive_file.ingest_worker_zip.output_path
  function_name    = "${var.project_name}-ingest-worker"
  role             = aws_iam_role.ingest_worker_role.arn
  handler          = "handler.handler"
  source_code_hash = data.archive_file.ingest_worker_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 300

  environment {
    variables = {
      PROCESSED_BUCKET = aws_s3_bucket.processed_output.bucket
      DYNAMODB_TABLE   = aws_dynamodb_table.documents.name
      OPENSEARCH_HOST  = aws_opensearchserverless_collection.vector_store.collection_endpoint
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.ingestion_queue.arn
  function_name    = aws_lambda_function.ingest_worker.arn
  batch_size       = 1
}

# --- Lambda: Query API ---

data "archive_file" "query_api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/query_api"
  output_path = "${path.module}/query_api.zip"
  excludes    = ["requirements.txt"]
}

resource "aws_iam_role" "query_api_role" {
  name = "${var.project_name}-query-api-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "query_api_basic" {
  role       = aws_iam_role.query_api_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "query_api_policy" {
  name = "${var.project_name}-query-api-policy"
  role = aws_iam_role.query_api_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
           "aoss:APIAccessAll"
        ]
        Resource = aws_opensearchserverless_collection.vector_store.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.documents.arn
      }
    ]
  })
}

resource "aws_lambda_function" "query_api" {
  filename         = data.archive_file.query_api_zip.output_path
  function_name    = "${var.project_name}-query-api"
  role             = aws_iam_role.query_api_role.arn
  handler          = "handler.handler"
  source_code_hash = data.archive_file.query_api_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30

  environment {
    variables = {
      DYNAMODB_TABLE   = aws_dynamodb_table.documents.name
      OPENSEARCH_HOST  = aws_opensearchserverless_collection.vector_store.collection_endpoint
    }
  }
}

# --- API Gateway ---

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "query_integration" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.query_api.invoke_arn
}

resource "aws_apigatewayv2_route" "query_route" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /query"
  target    = "integrations/${aws_apigatewayv2_integration.query_integration.id}"
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.query_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
