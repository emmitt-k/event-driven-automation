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
├── infra/                  # Infrastructure as Code (Terraform)
│   ├── main.tf             # Main configuration
│   ├── variables.tf        # Variable definitions
│   └── outputs.tf          # Output definitions
├── src/                    # Application Code
│   ├── ingest_worker/      # Lambda: Ingestion
│   │   ├── handler.py
│   │   └── requirements.txt # Specific dependencies (e.g., PDF parsers) to keep Lambda package small
│   └── query_api/          # Lambda: Query API
│       ├── handler.py
│       └── requirements.txt # Specific dependencies (e.g., opensearch-py)
├── tests/                  # Tests
├── README.md               # Project documentation
└── requirements.txt        # Dev dependencies (linting, testing, local mocks)
```

## Local Development & Testing

Since we use Terraform for infrastructure, we rely on the following strategies for local testing:

1.  **Unit Testing (Recommended)**:
    -   Use `pytest` and `moto` to mock AWS services (S3, SQS, DynamoDB) in memory.
    -   Mock Bedrock and OpenSearch calls using `unittest.mock`.
    -   This is the fastest way to test logic without needing real credentials or internet.

2.  **LocalStack (Full Emulation)**:
    -   Use [LocalStack](https://localstack.cloud/) to emulate AWS services locally.
    -   Deploy your Terraform config to LocalStack using `tflocal`.
    -   Great for testing the integration between services (e.g., S3 event -> SQS -> Lambda).

3.  **Hybrid Testing**:
    -   Run Python scripts locally that invoke your Lambda handler functions.
    -   Connect to *real* AWS development resources (e.g., a dev Bedrock endpoint) by setting AWS credentials in your environment.