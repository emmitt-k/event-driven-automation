# KMS Key for OpenSearch encryption
resource "aws_kms_key" "encryption_key" {
  description             = "KMS key for OpenSearch Serverless encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Allow administration of the key"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow OpenSearch Serverless to use the key"
        Effect = "Allow"
        Principal = {
          Service = "opensearchserverless.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-encryption-key"
    Type = "EncryptionKey"
  })
}

resource "aws_kms_alias" "encryption_key_alias" {
  name          = var.kms_key_alias
  target_key_id = aws_kms_key.encryption_key.key_id
}

# OpenSearch Serverless Collection
resource "aws_opensearchserverless_collection" "collection" {
  name = "${var.opensearch_collection_name}-${var.environment}"
  type = "VECTORSEARCH"

  standby_replicas = var.environment == "prod" ? "ENABLED" : "DISABLED"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-opensearch-collection"
    Type = "VectorSearch"
  })
}

# OpenSearch Serverless Access Policy
resource "aws_opensearchserverless_access_policy" "collection_access" {
  name = "${local.name_prefix}-collection-access"
  type = "data"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection",
          Resource = [
            "collection/${aws_opensearchserverless_collection.collection.id}"
          ],
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:DeleteCollectionItems",
            "aoss:UpdateCollectionItems",
            "aoss:DescribeCollectionItems"
          ]
        },
        {
          ResourceType = "index",
          Resource = [
            "index/${aws_opensearchserverless_collection.collection.id}/*"
          ],
          Permission = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:UpdateIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument",
            "aoss:DescribeIndex"
          ]
        }
      ],
      Principal = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name_prefix}-ingest-lambda-role",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name_prefix}-query-lambda-role"
      ]
    }
  ])
}

# OpenSearch Serverless Security Policy
resource "aws_opensearchserverless_security_policy" "encryption_policy" {
  name = "${local.name_prefix}-encryption-policy"
  type = "encryption"

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection",
        Resource = [
          "collection/${aws_opensearchserverless_collection.collection.id}"
        ]
      }
    ],
    AWSOwnedKey = var.enable_encryption ? false : true
    KmsARN = var.enable_encryption ? aws_kms_key.encryption_key.arn : null
  })
}

resource "aws_opensearchserverless_security_policy" "network_policy" {
  name = "${local.name_prefix}-network-policy"
  type = "network"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection",
          Resource = [
            "collection/${aws_opensearchserverless_collection.collection.id}"
          ]
        }
      ],
      AllowFromPublic = false
      SourceIPs = var.environment == "dev" ? ["0.0.0.0/0"] : []
    }
  ])
}

# OpenSearch Serverless VPC Endpoint (for production)
resource "aws_opensearchserverless_vpc_endpoint" "vpc_endpoint" {
  count = var.environment == "prod" ? 1 : 0
  
  name = "${local.name_prefix}-vpc-endpoint"
  vpc_id = aws_vpc.main[0].id
  subnet_ids = aws_subnet.private[0].*.id
  security_group_ids = [aws_security_group.opensearch[0].id]
}

# VPC resources for production
resource "aws_vpc" "main" {
  count = var.environment == "prod" ? 1 : 0
  
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
    Type = "VPC"
  })
}

resource "aws_subnet" "private" {
  count = var.environment == "prod" ? 2 : 0
  
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Type = "PrivateSubnet"
  })
}

resource "aws_security_group" "opensearch" {
  count = var.environment == "prod" ? 1 : 0
  
  name_prefix = "${local.name_prefix}-opensearch-"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main[0].cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-opensearch-sg"
    Type = "SecurityGroup"
  })
}

data "aws_availability_zones" "available" {
  state = "available"
}