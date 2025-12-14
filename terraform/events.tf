# EventBridge Event Bus
resource "aws_cloudwatch_event_bus" "event_bus" {
  name = "${local.name_prefix}-event-bus"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-event-bus"
    Type = "EventBus"
  })
}

# SQS Queue for file processing
resource "aws_sqs_queue" "processing_queue" {
  name                        = "${local.name_prefix}-processing-queue"
  visibility_timeout_seconds    = 300
  message_retention_seconds    = 1209600 # 14 days
  max_message_size            = 262144    # 256 KB
  receive_wait_time_seconds   = 20
  sqs_managed_sse_enabled    = var.enable_encryption

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-processing-queue"
    Type = "SQSQueue"
  })
}

# SQS Queue Policy to allow EventBridge to send messages
resource "aws_sqs_queue_policy" "processing_queue_policy" {
  queue_url = aws_sqs_queue.processing_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.processing_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.s3_upload_event.arn
          }
        }
      }
    ]
  })
}

# EventBridge Rule for S3 upload events
resource "aws_cloudwatch_event_rule" "s3_upload_event" {
  name          = "${local.name_prefix}-s3-upload-event"
  description   = "Capture S3 object created events"
  event_bus_name = aws_cloudwatch_event_bus.event_bus.name

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.raw_files.bucket]
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-upload-event"
    Type = "EventRule"
  })
}

# EventBridge Target to send S3 events to SQS
resource "aws_cloudwatch_event_target" "s3_to_sqs" {
  rule      = aws_cloudwatch_event_rule.s3_upload_event.name
  event_bus_name = aws_cloudwatch_event_bus.event_bus.name
  target_id = "ProcessingQueueTarget"
  arn       = aws_sqs_queue.processing_queue.arn

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
      size   = "$.detail.object.size"
      etag   = "$.detail.object.etag"
      time   = "$.time"
    }
    input_template = <<EOF
{
  "bucket": <bucket>,
  "key": <key>,
  "size": <size>,
  "etag": <etag>,
  "event_time": <time>,
  "event_type": "s3:ObjectCreated:*"
}
EOF
  }
}

# Lambda Event Source Mapping for SQS to Ingest Lambda
resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.processing_queue.arn
  function_name    = aws_lambda_function.ingest.function_name
  batch_size       = 5
  maximum_batching_window_in_seconds = 60

  depends_on = [
    aws_iam_role_policy.ingest_lambda_policy
  ]
}

# EventBridge Rule for processing status events
resource "aws_cloudwatch_event_rule" "processing_status_event" {
  name          = "${local.name_prefix}-processing-status-event"
  description   = "Capture processing status events"
  event_bus_name = aws_cloudwatch_event_bus.event_bus.name

  event_pattern = jsonencode({
    source      = ["event-driven-automation.processing"]
    detail-type = ["Processing Status"]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-processing-status-event"
    Type = "EventRule"
  })
}

# CloudWatch Log Group for EventBridge
resource "aws_cloudwatch_log_group" "eventbridge_logs" {
  name              = "/aws/events/${aws_cloudwatch_event_bus.event_bus.name}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eventbridge-logs"
    Type = "LogGroup"
  })
}

# Dead Letter Queue for SQS
resource "aws_sqs_queue" "processing_dlq" {
  name                        = "${local.name_prefix}-processing-dlq"
  visibility_timeout_seconds    = 300
  message_retention_seconds    = 1209600 # 14 days
  max_message_size            = 262144    # 256 KB
  sqs_managed_sse_enabled    = var.enable_encryption

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-processing-dlq"
    Type = "SQSQueue"
  })
}

# Redrive Policy for main queue
resource "aws_sqs_queue_redrive_allow_policy" "processing_queue_redrive" {
  queue_url = aws_sqs_queue.processing_queue.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.processing_dlq.arn]
  })
}

# Update main queue with redrive policy
resource "aws_sqs_queue" "processing_queue_with_dlq" {
  name                        = "${local.name_prefix}-processing-queue"
  visibility_timeout_seconds    = 300
  message_retention_seconds    = 1209600 # 14 days
  max_message_size            = 262144    # 256 KB
  receive_wait_time_seconds   = 20
  sqs_managed_sse_enabled    = var.enable_encryption
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-processing-queue"
    Type = "SQSQueue"
  })

  depends_on = [aws_sqs_queue.processing_dlq]
}

# CloudWatch Alarms for SQS
resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  alarm_name          = "${local.name_prefix}-sqs-queue-depth-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "ApproximateNumberOfMessagesVisible"
  namespace         = "AWS/SQS"
  period            = "300"
  statistic         = "Sum"
  threshold         = "100"
  alarm_description = "This metric monitors the SQS queue depth"
  alarm_actions     = []

  dimensions = {
    QueueName = aws_sqs_queue.processing_queue_with_dlq.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sqs-queue-depth-alarm"
    Type = "CloudWatchAlarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "sqs_dlq_messages" {
  alarm_name          = "${local.name_prefix}-sqs-dlq-messages-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name        = "ApproximateNumberOfMessagesVisible"
  namespace         = "AWS/SQS"
  period            = "300"
  statistic         = "Sum"
  threshold         = "0"
  alarm_description = "This metric monitors messages in the DLQ"
  alarm_actions     = []

  dimensions = {
    QueueName = aws_sqs_queue.processing_dlq.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sqs-dlq-messages-alarm"
    Type = "CloudWatchAlarm"
  })
}