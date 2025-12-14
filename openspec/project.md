# Project Context

## Purpose
An end-to-end, event-driven system that ingests files from S3, processes them with LLMs for extraction and embeddings, stores vector data, and exposes APIs for search. The system enables automated processing of uploaded files through AI-powered extraction and semantic search capabilities.

## Tech Stack
- **Compute**: AWS Lambda (Python/Node.js)
- **Orchestration**: EventBridge & SQS for decoupled message passing
- **AI/ML**: Amazon Bedrock (Claude for extraction, Titan for embeddings)
- **Storage**:
  - S3: Raw files and processed JSON
  - DynamoDB: Metadata and processing status
  - OpenSearch Serverless: Vector index for semantic search
- **API**: API Gateway (HTTP) with Cognito/IAM auth
- **Infrastructure**: Terraform for Infrastructure as Code
- **Testing**: pytest, moto, LocalStack for local testing

## Project Conventions

### Code Style
- Python for Lambda functions
- Separate requirements.txt files for each Lambda to keep packages small
- Infrastructure as Code using Terraform
- Modular project structure with separate directories for infrastructure, source code, and tests

### Architecture Patterns
- **Event-driven architecture**: S3 events trigger processing via EventBridge and SQS
- **Serverless architecture**: All compute components use AWS Lambda
- **Microservices pattern**: Separate Lambda functions for ingestion and query operations
- **Idempotency**: Use S3 ETag/Key as unique identifiers to prevent duplicate processing

### Testing Strategy
1. **Unit Testing**: Use pytest and moto to mock AWS services in memory
2. **LocalStack**: Full AWS emulation for integration testing
3. **Hybrid Testing**: Local Python scripts with real AWS development resources
4. Mock Bedrock and OpenSearch calls using unittest.mock

### Git Workflow
[Not specified in README - to be determined by team]

## Domain Context
This is an AI-powered document processing and search system that:
- Automatically processes uploaded files using LLMs
- Extracts structured data and generates embeddings
- Enables semantic search through vector embeddings
- Uses event-driven patterns for scalable, serverless processing

## Important Constraints
- **Security**: Least privilege IAM roles, VPC endpoints for private connectivity, KMS encryption
- **Cost**: Pay-per-use model with major costs from Bedrock tokens and OpenSearch OCU hours
- **Scalability**: Serverless architecture to handle variable workloads
- **Reliability**: Idempotent processing to prevent duplicate work

## External Dependencies
- **Amazon Bedrock**: For LLM-based extraction and embedding generation
- **OpenSearch Serverless**: For vector storage and semantic search
- **AWS Services**: S3, DynamoDB, Lambda, SQS, EventBridge, API Gateway, CloudWatch
- **LocalStack**: For local development and testing
