# Troubleshooting Guide

This guide covers common issues and solutions when deploying and managing the event-driven automation infrastructure.

## Terraform Issues

### Initialization Problems

**Error: "Failed to instantiate provider"**
- **Cause**: Terraform version incompatibility or missing provider plugins
- **Solution**: 
  ```bash
  terraform version  # Should be >= 1.5.0
  terraform init -upgrade  # Re-initialize with latest providers
  ```

**Error: "S3 bucket already exists"**
- **Cause**: Bucket name collision or partial deployment
- **Solution**:
  ```bash
  # Import existing bucket
  terraform import aws_s3_bucket.raw_files your-bucket-name
  # Or use different bucket prefix in terraform.tfvars
  ```

### State Management Issues

**Error: "State lock"**
- **Cause**: Another Terraform process is running
- **Solution**:
  ```bash
  # Force unlock (use with caution)
  terraform force-unlock LOCK_ID
  
  # Or wait for other process to complete
  ```

**Error: "Terraform state file not found"**
- **Cause**: Missing state file or backend not configured
- **Solution**:
  ```bash
  # Configure backend before running apply
  terraform init \
    -backend-config="bucket=your-state-bucket" \
    -backend-config="key=event-driven-automation/terraform.tfstate" \
    -backend-config="region=us-east-1"
  ```

## AWS Service Issues

### Lambda Function Failures

**Error: "Lambda timeout"**
- **Cause**: Function execution exceeds configured timeout
- **Solution**:
  - Increase `lambda_timeout` in terraform.tfvars
  - Optimize Lambda code for better performance
  - Check CloudWatch logs for bottlenecks

**Error: "Out of memory"**
- **Cause**: Lambda function exceeds memory limit
- **Solution**:
  - Increase `lambda_memory_size` in terraform.tfvars
  - Profile memory usage in CloudWatch

**Error: "Permission denied"**
- **Cause**: IAM role missing required permissions
- **Solution**:
  ```bash
  # Check IAM policy in Terraform outputs
  terraform output
  
  # Verify role attachments
  aws iam list-attached-role-policies --role-name your-lambda-role
  ```

### S3 Access Issues

**Error: "Access Denied" on S3 operations
- **Cause**: Incorrect IAM permissions or bucket policies
- **Solution**:
  - Verify bucket policy allows Lambda access
  - Check IAM role includes S3 permissions
  - Ensure VPC endpoints if using VPC

**Error: "No such bucket"**
- **Cause**: Bucket not created or incorrect region
- **Solution**:
  ```bash
  # List buckets to verify
  aws s3 ls
  
  # Check specific bucket
  aws s3 ls s3://your-bucket-name
  ```

### DynamoDB Issues

**Error: "ProvisionedThroughputExceededException"**
- **Cause**: Exceeding provisioned capacity
- **Solution**: 
  - Use on-demand billing mode (`dynamodb_billing_mode = "PAY_PER_REQUEST"`)
  - Or increase provisioned capacity

**Error: "ValidationException"**
- **Cause**: Invalid table schema or operations
- **Solution**:
  - Check table definition in Terraform
  - Verify data types match schema
  - Review CloudWatch logs for details

### OpenSearch Serverless Issues

**Error: "Access denied" to OpenSearch
- **Cause**: Missing data access policies
- **Solution**:
  - Verify `aws_opensearchserverless_access_policy` includes Lambda roles
  - Check security policy allows network access
  - Ensure collection is active

**Error: "Resource not found"**
- **Cause**: Collection not ready or incorrect endpoint
- **Solution**:
  ```bash
  # Check collection status
  aws opensearchserverless list-collections
  
  # Verify endpoint URL
  terraform output opensearch_collection_endpoint
  ```

### API Gateway Issues

**Error: "502 Bad Gateway"**
- **Cause**: Lambda function errors or timeout
- **Solution**:
  - Check Lambda CloudWatch logs
  - Verify Lambda timeout settings
  - Test Lambda function directly

**Error: "403 Forbidden"**
- **Cause**: Missing API permissions or incorrect auth
- **Solution**:
  - Check API Gateway authorization settings
  - Verify IAM policies for API access
  - Test with proper authentication headers

## EventBridge and SQS Issues

### Event Routing Problems

**Error: "Events not triggering Lambda"
- **Cause**: Incorrect EventBridge rules or targets
- **Solution**:
  ```bash
  # Check EventBridge rules
  aws events list-rules
  
  # Verify target configuration
  aws events list-targets --rule your-rule-name
  ```

**Error: "SQS messages not processed"**
- **Cause**: Lambda trigger not configured or permissions
- **Solution**:
  - Verify `aws_lambda_event_source_mapping` exists
  - Check SQS queue policy allows Lambda access
  - Review DLQ for failed messages

## Environment-Specific Issues

### Development Environment

**Error: "Resource limits exceeded"**
- **Cause**: AWS account limits in dev account
- **Solution**:
  - Request service limit increases
  - Use smaller resource sizes in dev config
  - Clean up unused resources regularly

### Production Environment

**Error: "VPC endpoint not accessible"
- **Cause**: VPC configuration or security groups
- **Solution**:
  - Check VPC route tables
  - Verify security group rules
  - Test connectivity from Lambda functions

## Performance Issues

### Slow Processing

**Symptoms**: Files take too long to process
- **Causes**:
  - Large file sizes
  - Bedrock API rate limits
  - Insufficient Lambda memory
- **Solutions**:
  - Implement file size limits
  - Add retry logic with exponential backoff
  - Increase Lambda memory allocation

### High Costs

**Symptoms**: Unexpected AWS charges
- **Common Causes**:
  - Provisioned instead of on-demand resources
  - Unused resources running
  - Data transfer costs
- **Solutions**:
  - Use CloudWatch cost explorer
  - Set up billing alerts
  - Review resource utilization

## Debugging Tools

### Terraform Debugging

```bash
# Enable detailed logging
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform.log

# Plan with detailed output
terraform plan -detailed-exitcode
```

### AWS CLI Debugging

```bash
# Enable debug logging
export AWS_CLI_FILE_ENCODING=UTF-8
export AWS_DEFAULT_OUTPUT=json
export AWS_PAGER=""

# Test API calls
aws s3 ls --debug
```

### Lambda Testing

```bash
# Test Lambda locally
sam local invoke function function-name --event event.json

# Or use Terraform console
terraform console
```

## Common Solutions

### 1. Restart Deployment

If experiencing persistent issues:
```bash
make clean          # Clean artifacts
make destroy         # Remove existing resources
make init           # Re-initialize
make deploy-dev     # Fresh deployment
```

### 2. Check Dependencies

Ensure all required tools are installed:
```bash
terraform --version
aws --version
docker --version
python --version
```

### 3. Verify Configuration

Validate all configuration files:
```bash
make lint           # Check Terraform syntax
terraform validate   # Validate configuration
```

### 4. Monitor Logs

Always check logs when troubleshooting:
- **Terraform**: Check plan/apply output
- **CloudWatch**: Lambda and API logs
- **X-Ray**: Request tracing (if enabled)
- **AWS Config**: Configuration compliance

## Getting Help

### Internal Resources
- Check this document first
- Review `make help` for available commands
- Examine Terraform outputs: `terraform output`

### External Resources
- [AWS Documentation](https://docs.aws.amazon.com/)
- [Terraform Documentation](https://www.terraform.io/docs/)
- [OpenSearch Serverless Guide](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless.html)

### Community Support
- GitHub Issues: Create detailed bug reports
- AWS Forums: Service-specific questions
- Stack Overflow: General troubleshooting

## Prevention

### Regular Maintenance
- Run `make security-scan` regularly
- Monitor costs with CloudWatch
- Keep dependencies updated
- Test disaster recovery procedures

### Best Practices
- Use environment-specific configurations
- Implement proper tagging for cost tracking
- Enable all logging and monitoring
- Test changes in non-production environments first