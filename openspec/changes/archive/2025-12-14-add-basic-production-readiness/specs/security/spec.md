## ADDED Requirements

### Requirement: Fix Bedrock IAM Policy Wildcard Access
The system SHALL fix the overly permissive Bedrock IAM policy that uses wildcard resource access.

#### Scenario: Scoped Ingest Worker Bedrock Access
- **WHEN** ingest worker Lambda invokes Bedrock models
- **THEN** IAM policy at [`infra/main.tf:270`](infra/main.tf:270) SHALL be scoped to specific model ARNs
- **AND** SHALL not use "Resource = "*" for bedrock:InvokeModel

#### Scenario: Scoped Query API Bedrock Access
- **WHEN** query API Lambda invokes Bedrock models
- **THEN** IAM policy at [`infra/main.tf:348`](infra/main.tf:348) SHALL be scoped to specific model ARNs
- **AND** SHALL not use "Resource = "*" for bedrock:InvokeModel

### Requirement: API Gateway Authentication
The system SHALL implement the IAM authentication mentioned in README.

#### Scenario: IAM Authentication Implementation
- **WHEN** clients access the query API
- **THEN** API Gateway SHALL require IAM signature authentication
- **AND** SHALL reject unauthorized requests with HTTP 401
- **AND** SHALL align with README line 101 "API Gateway (HTTP) with Cognito/IAM auth"

### Requirement: Input Validation
The system SHALL validate API request inputs.

#### Scenario: Query Parameter Validation
- **WHEN** the query API at [`src/query_api/handler.py`](src/query_api/handler.py) receives a request
- **THEN** it SHALL validate the query parameter exists and is not empty
- **AND** SHALL reject malformed requests with HTTP 400

### Requirement: Error Handling and Retry Logic
The system SHALL implement retry logic for AWS SDK failures.

#### Scenario: Ingest Worker Retries
- **WHEN** AWS SDK calls in [`src/ingest_worker/handler.py`](src/ingest_worker/handler.py) fail with transient errors
- **THEN** the system SHALL retry with exponential backoff
- **AND** SHALL log retry attempts for debugging

#### Scenario: Query API Retries
- **WHEN** AWS SDK calls in [`src/query_api/handler.py`](src/query_api/handler.py) fail with transient errors
- **THEN** the system SHALL retry with exponential backoff
- **AND** SHALL log retry attempts for debugging

### Requirement: Basic Monitoring Alarms
The system SHALL have CloudWatch alarms for critical metrics.

#### Scenario: Lambda Error Alarm
- **WHEN** Lambda error rate exceeds 5%
- **THEN** a CloudWatch alarm SHALL be triggered
- **AND** SHALL notify operations team

#### Scenario: DLQ Depth Alarm
- **WHEN** DLQ message count exceeds 10
- **THEN** a CloudWatch alarm SHALL be triggered
- **AND** SHALL indicate processing failures requiring attention