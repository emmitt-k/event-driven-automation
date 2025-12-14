# Change: Add Basic Production Readiness

## Why
Current implementation has critical security and reliability gaps that prevent safe production deployment. Focus on essential items only to get to production quickly.

## What Changes
- Fix overly permissive IAM policies (line 270: Resource = "*" for Bedrock access)
- Add API Gateway IAM authentication (README mentions "Cognito/IAM auth" but not implemented)
- Add basic error handling and retry logic in Lambda functions
- Add input validation for query API endpoint
- Add basic CloudWatch alarms for DLQ and Lambda errors

## Impact
- Affected specs: security
- Affected code: Lambda functions, Terraform configuration ([`infra/main.tf`](infra/main.tf))
- **BREAKING**: IAM policy changes will require explicit permission updates