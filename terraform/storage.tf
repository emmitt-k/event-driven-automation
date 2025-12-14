# S3 Buckets
resource "aws_s3_bucket" "raw_files" {
  bucket = "${var.s3_bucket_prefix}-${var.environment}-raw-files-${data.aws_caller_identity.current.account_id}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-raw-files"
    Type = "RawFileStorage"
  })
}

resource "aws_s3_bucket_versioning" "raw_files" {
  bucket = aws_s3_bucket.raw_files.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_files" {
  bucket = aws_s3_bucket.raw_files.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "raw_files" {
  bucket = aws_s3_bucket.raw_files.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Processed files bucket
resource "aws_s3_bucket" "processed_files" {
  bucket = "${var.s3_bucket_prefix}-${var.environment}-processed-files-${data.aws_caller_identity.current.account_id}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-processed-files"
    Type = "ProcessedFileStorage"
  })
}

resource "aws_s3_bucket_versioning" "processed_files" {
  bucket = aws_s3_bucket.processed_files.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_files" {
  bucket = aws_s3_bucket.processed_files.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "processed_files" {
  bucket = aws_s3_bucket.processed_files.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket notification for EventBridge
resource "aws_s3_bucket_notification" "raw_files_notification" {
  bucket = aws_s3_bucket.raw_files.id

  eventbridge = true
}

# DynamoDB Tables
resource "aws_dynamodb_table" "metadata" {
  name           = "${var.dynamodb_table_prefix}-${var.environment}-metadata"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "file_id"
  
  attribute {
    name = "file_id"
    type = "S"
  }

  attribute {
    name = "upload_date"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name     = "ByUploadDate"
    hash_key = "upload_date"
    projection_type = "ALL"
  }

  global_secondary_index {
    name     = "ByStatus"
    hash_key = "status"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-metadata"
    Type = "MetadataStorage"
  })
}

resource "aws_dynamodb_table" "processing_status" {
  name           = "${var.dynamodb_table_prefix}-${var.environment}-processing-status"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "task_id"
  
  attribute {
    name = "task_id"
    type = "S"
  }

  attribute {
    name = "file_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name     = "ByFileId"
    hash_key = "file_id"
    projection_type = "ALL"
  }

  global_secondary_index {
    name     = "ByStatus"
    hash_key = "status"
    range_key = "created_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-processing-status"
    Type = "ProcessingStatusStorage"
  })
}