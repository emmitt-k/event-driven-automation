## 1. Critical Security Fixes
- [ ] 1.1 Fix IAM policy in [`infra/main.tf:270`](infra/main.tf:270) to scope Bedrock access to specific models
- [ ] 1.2 Fix IAM policy in [`infra/main.tf:348`](infra/main.tf:348) to scope Bedrock access to specific models
- [ ] 1.3 Add API Gateway IAM authentication (missing per README line 101)
- [ ] 1.4 Add basic input validation to [`src/query_api/handler.py`](src/query_api/handler.py)

## 2. Basic Error Handling
- [ ] 2.1 Add retry logic with exponential backoff to [`src/ingest_worker/handler.py`](src/ingest_worker/handler.py)
- [ ] 2.2 Add retry logic with exponential backoff to [`src/query_api/handler.py`](src/query_api/handler.py)
- [ ] 2.3 Add proper error logging and handling in both Lambda functions

## 3. Basic Monitoring
- [ ] 3.1 Add CloudWatch alarm for Lambda errors to [`infra/main.tf`](infra/main.tf)
- [ ] 3.2 Add CloudWatch alarm for DLQ depth to [`infra/main.tf`](infra/main.tf)
- [ ] 3.3 Add basic structured logging to both Lambda handlers

## 4. Production Deployment
- [ ] 4.1 Update Terraform with security fixes and monitoring
- [ ] 4.2 Create Makefile for infrastructure deployment and management
- [ ] 4.3 Test deployment in staging environment
- [ ] 4.4 Deploy to production with rollback plan