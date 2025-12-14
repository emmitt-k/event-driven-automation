# Event-Driven AI Automation Worker on AWS

An end-to-end, event-driven system that ingests files from S3, processes them with LLMs for extraction and embeddings, stores vector data, and exposes APIs for search.

## Goals
- **Automated Ingestion**: Trigger processing on file upload.
- **AI Processing**: Extract structured data and generate embeddings using Amazon Bedrock.
- **Vector Search**: Store and query vectors using OpenSearch Serverless.
- **Scalability**: Serverless architecture (Lambda, SQS, EventBridge).

## Architecture

```
                +---------------------------+
                |         Clients           |
                |  (UI, services, CLI)      |
                +-------------+-------------+
                              |
                        1) Upload via
                           pre-signed URL
                              |
                              v
                    +-------------------+
                    |   S3 Bucket       |
                    |  raw-input        |
                    +---------+---------+
                              | 2) Event
                              v
                    +-------------------+
                    |  EventBridge Bus  |
                    |  (S3 ObjectCreated|
                    |   routed to SQS)  |
                    +---------+---------+
                              |
                          3) Enqueue
                              |
                              v
                    +-------------------+
                    |       SQS         |
                    | ingestion-queue   |
                    +---------+---------+
                              |
                        4) Trigger Lambda
                              |
                              v
    +---------------------------------------------------------------+
    |                      Lambda: ingest-worker                    |
    |  - Fetch object from S3                                       |
    |  - Call Bedrock LLM (extraction)                              |
    |  - Call Bedrock Embeddings (vector)                           |
    |  - Store metadata in DynamoDB                                 |
    |  - Store vector in OpenSearch Serverless                      |
    |  - Write processed JSON to S3 processed-output                |
    +---------------------------------------------------------------+
                              |
                         5) Metrics/Logs
                              |
                              v
                     +------------------+
                     |  CloudWatch      |
                     |  Logs/Metrics    |
                     +------------------+

                              ^
                              |
                     6) Query APIs
                              |
                              v
     +--------------------+         +-------------------------------+
     | API Gateway (HTTP) | ----->  | Lambda: query-api             |
     |                    |         | - Vector search (OpenSearch)  |
     |                    |         | - Return ranked results       |
     +---------+----------+         +-------------------------------+
               |
               v
           +--------+
           | Clients|
           +--------+
```

## Workflow

1.  **Upload**: Client uploads file to S3 (`raw-input`).
2.  **Trigger**: S3 event triggers EventBridge -> SQS (`ingestion-queue`).
3.  **Process**: `ingest-worker` Lambda:
    -   Retrieves file.
    -   Calls **Bedrock** to extract JSON and generate embeddings.
    -   Stores metadata in **DynamoDB** and vectors in **OpenSearch Serverless**.
    -   Saves output to S3 (`processed-output`).
4.  **Query**: Client calls API Gateway -> `query-api` Lambda -> OpenSearch for vector search.

## Key Components

-   **Compute**: AWS Lambda (Python/Node.js) for ingestion and querying.
-   **Orchestration**: EventBridge & SQS for decoupled, reliable message passing.
-   **AI/ML**: Amazon Bedrock (Claude for extraction, Titan for embeddings).
-   **Storage**:
    -   **S3**: Raw files and processed JSON.
    -   **DynamoDB**: Metadata and processing status.
    -   **OpenSearch Serverless**: Vector index for semantic search.
-   **API**: API Gateway (HTTP) with Cognito/IAM auth.

## Considerations

-   **Idempotency**: Use S3 ETag/Key as unique identifiers to prevent duplicate processing.
-   **Security**: Least privilege IAM roles, VPC endpoints for private connectivity, and KMS encryption.
-   **Observability**: CloudWatch for logs, metrics (token usage, latency), and alarms (DLQ depth).
-   **Cost**: Pay-per-use model. Major costs are Bedrock tokens and OpenSearch OCU hours.

## Project Structure

```
.
├── terraform/               # Infrastructure as Code (Terraform)
│   ├── main.tf             # Main configuration
│   ├── variables.tf        # Variable definitions
│   ├── outputs.tf          # Output definitions
│   ├── storage.tf         # S3 and DynamoDB resources
│   ├── search.tf          # OpenSearch Serverless resources
│   ├── compute.tf         # Lambda functions
│   ├── api.tf            # API Gateway resources
│   ├── events.tf         # EventBridge and SQS
│   ├── environments/      # Environment-specific configs
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── tmp/              # Lambda package artifacts
├── src/                    # Application Code
│   ├── ingest_worker/      # Lambda: Ingestion
│   │   ├── handler.py
│   │   └── requirements.txt # Specific dependencies (e.g., PDF parsers) to keep Lambda package small
│   └── query_api/          # Lambda: Query API
│       ├── handler.py
│       └── requirements.txt # Specific dependencies (e.g., opensearch-py)
├── tests/                  # Tests
├── openspec/              # OpenSpec specifications
├── Makefile               # Deployment automation
├── README.md              # Project documentation
└── requirements.txt       # Dev dependencies (linting, testing, local mocks)
```

## Local Development & Testing

Since we use Terraform for infrastructure, we rely on following strategies for local testing:

1.  **Unit Testing (Recommended)**:
    -   Use `pytest` and `moto` to mock AWS services (S3, SQS, DynamoDB) in memory.
    -   Mock Bedrock and OpenSearch calls using `unittest.mock`.
    -   This is the fastest way to test logic without needing real credentials or internet.

2.  **LocalStack (Full Emulation)**:
    -   Use [LocalStack](https://localstack.cloud/) to emulate AWS services locally.
    -   Deploy your Terraform config to LocalStack using `tflocal`.
    -   Great for testing integration between services (e.g., S3 event -> SQS -> Lambda).

3.  **Hybrid Testing**:
    -   Run Python scripts locally that invoke your Lambda handler functions.
    -   Connect to *real* AWS development resources (e.g., a dev Bedrock endpoint) by setting AWS credentials in your environment.

## Quick Start

### Prerequisites
- AWS CLI configured with appropriate credentials
- Terraform installed
- Python 3.9+ with pip
- Docker (for LocalStack testing)

### Deployment

The project now uses a comprehensive Makefile-based deployment system:

```bash
# 1. Initialize Terraform (first time setup)
make init

# 2. Deploy to development environment
make deploy-dev

# 3. Deploy to staging environment
make deploy-staging

# 4. Deploy to production environment
make deploy-prod
```

#### Available Makefile Targets

**Basic Operations:**
- `make help` - Show all available targets
- `make init` - Initialize Terraform working directory
- `make validate` - Validate Terraform configuration
- `make plan` - Show execution plan
- `make apply` - Apply configuration
- `make destroy` - Destroy infrastructure

**Environment-Specific:**
- `make deploy-dev` - Deploy to development
- `make deploy-staging` - Deploy to staging
- `make deploy-prod` - Deploy to production
- `make plan-dev` - Show plan for development
- `make plan-staging` - Show plan for staging
- `make plan-prod` - Show plan for production

**Utilities:**
- `make clean` - Clean temporary files
- `make format` - Format Terraform code
- `make lint` - Lint and validate configuration
- `make package-lambda` - Package Lambda functions

#### Environment Configuration

Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and customize for your needs. Environment-specific configurations are available in:

- `terraform/environments/dev/terraform.tfvars`
- `terraform/environments/staging/terraform.tfvars`
- `terraform/environments/prod/terraform.tfvars`

#### Examples
```bash
# Deploy to development with custom variables
cd terraform
terraform apply -var-file=environments/dev/terraform.tfvars

# Plan changes for production
make plan-prod

# Destroy development environment
make destroy-dev
```

### Development Workflow

1. **Setup**: Initialize with `make init`
2. **Configure**: Copy and customize `terraform/terraform.tfvars`
3. **Plan**: Review changes with `make plan-dev`
4. **Deploy**: Apply infrastructure with `make deploy-dev`
5. **Develop**: Make changes to Lambda code in `src/`
6. **Update**: Re-package and deploy with `make package-lambda && make deploy-dev`
7. **Repeat**: Continue development cycle

### Advanced Usage

**State Management:**
- `make state-list` - List Terraform workspaces
- `make state-show` - Show current state
- `make backup-state` - Backup current state

**Security & Compliance:**
- `make security-scan` - Run security scan with tfsec
- `make cost-estimate` - Estimate infrastructure costs

**Custom Environments:**
```bash
# Deploy to custom environment
ENV=custom make deploy-custom
```

## Infrastructure Components

### Storage Layer
- **S3 Buckets**: Raw file storage and processed output
- **DynamoDB Tables**: Metadata tracking and processing status
- **OpenSearch Serverless**: Vector index for semantic search

### Compute Layer
- **Lambda Functions**: 
  - `ingest-worker`: Processes uploaded files
  - `query-api`: Handles search requests
- **IAM Roles**: Least-privilege access policies

### API Layer
- **API Gateway**: RESTful HTTP endpoints
- **Endpoints**:
  - `POST /documents` - Upload and process files
  - `GET /documents/{id}` - Retrieve document metadata
  - `POST /search` - Semantic search queries

### Event Layer
- **EventBridge**: Event routing and orchestration
- **SQS**: Reliable message delivery
- **CloudWatch**: Logging, monitoring, and alerting

## Security Considerations

- **Encryption**: KMS-managed encryption for all data at rest
- **Network**: VPC endpoints for production workloads
- **Access**: IAM least-privilege principle
- **Compliance**: Audit logging and monitoring

## Cost Optimization

- **Serverless**: Pay-per-use pricing model
- **Event-driven**: No idle resources
- **Monitoring**: Cost alerts and usage tracking
- **Scaling**: Automatic scaling based on demand