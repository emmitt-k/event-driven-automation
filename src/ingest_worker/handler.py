import json
import os
import boto3
import time
import logging
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth
from botocore.exceptions import ClientError
from botocore.config import Config

# Configure structured logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Configure retry policy
retry_config = Config(
    retries={
        'max_attempts': 3,
        'mode': 'adaptive'
    }
)

# Clients
s3 = boto3.client('s3', config=retry_config)
dynamodb = boto3.client('dynamodb', config=retry_config)
bedrock = boto3.client('bedrock-runtime', config=retry_config)

# Config
PROCESSED_BUCKET = os.environ.get('PROCESSED_BUCKET')
TABLE_NAME = os.environ.get('DYNAMODB_TABLE')
OPENSEARCH_HOST = os.environ.get('OPENSEARCH_HOST')
REGION = os.environ.get('AWS_REGION', 'us-east-1')

# OpenSearch Client Setup
def get_opensearch_client():
    credentials = boto3.Session().get_credentials()
    auth = AWSV4SignerAuth(credentials, REGION, 'aoss')
    
    # Remove https:// prefix if present for host
    host = OPENSEARCH_HOST.replace("https://", "") if OPENSEARCH_HOST else ""

    return OpenSearch(
        hosts=[{'host': host, 'port': 443}],
        http_auth=auth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
        pool_maxsize=20
    )

def extract_content(bucket, key):
    """
    Get file content from S3. 
    For this MVP, we assume text files. 
    For PDF/Docx, we would use a library like pypdf or textract.
    """
    obj = s3.get_object(Bucket=bucket, Key=key)
    return obj['Body'].read().decode('utf-8')

def call_bedrock_extraction(text):
    """
    Call Claude to extract structured data.
    Implements retry logic with exponential backoff.
    """
    prompt = f"""
    Human: Extract the following fields from the text below as JSON:
    - title
    - summary
    - tags (list of strings)
    - date

    Text:
    {text[:2000]}
    
    Assistant: {{
    """
    
    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1000,
        "messages": [
            {
                "role": "user",
                "content": prompt
            }
        ]
    })

    max_retries = 3
    base_delay = 1  # seconds
    
    for attempt in range(max_retries):
        try:
            logger.info(f"Calling Bedrock Extraction, attempt {attempt + 1}/{max_retries}")
            response = bedrock.invoke_model(
                modelId='anthropic.claude-3-sonnet-20240229-v1:0', # Make sure this model is enabled
                body=body
            )
            response_body = json.loads(response['body'].read())
            # Simple parsing logic - in prod, use more robust JSON extraction
            content = response_body['content'][0]['text']
            # Attempt to find JSON start/end if model chats
            start = content.find('{')
            end = content.rfind('}') + 1
            if start != -1 and end != -1:
                result = json.loads(content[start:end])
                logger.info("Successfully extracted structured data")
                return result
            return {}
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code in ['ThrottlingException', 'ServiceQuotaExceededException', 'InternalFailure']:
                if attempt < max_retries - 1:
                    delay = base_delay * (2 ** attempt)  # Exponential backoff
                    logger.warning(f"Bedrock call failed with {error_code}, retrying in {delay}s: {e}")
                    time.sleep(delay)
                    continue
                else:
                    logger.error(f"Bedrock call failed after {max_retries} attempts: {e}")
                    return {"error": str(e)}
            else:
                logger.error(f"Bedrock call failed with non-retryable error: {e}")
                return {"error": str(e)}
        except Exception as e:
            logger.error(f"Unexpected error calling Bedrock Extraction: {e}")
            return {"error": str(e)}

def call_bedrock_embedding(text):
    """
    Call Titan Embeddings to generate vector.
    Implements retry logic with exponential backoff.
    """
    body = json.dumps({
        "inputText": text[:8000] # Titan limit
    })
    
    max_retries = 3
    base_delay = 1  # seconds
    
    for attempt in range(max_retries):
        try:
            logger.info(f"Calling Bedrock Embeddings, attempt {attempt + 1}/{max_retries}")
            response = bedrock.invoke_model(
                modelId='amazon.titan-embed-text-v1',
                body=body
            )
            response_body = json.loads(response['body'].read())
            logger.info("Successfully generated embedding")
            return response_body['embedding']
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code in ['ThrottlingException', 'ServiceQuotaExceededException', 'InternalFailure']:
                if attempt < max_retries - 1:
                    delay = base_delay * (2 ** attempt)  # Exponential backoff
                    logger.warning(f"Bedrock call failed with {error_code}, retrying in {delay}s: {e}")
                    time.sleep(delay)
                    continue
                else:
                    logger.error(f"Bedrock call failed after {max_retries} attempts: {e}")
                    return []
            else:
                logger.error(f"Bedrock call failed with non-retryable error: {e}")
                return []
        except Exception as e:
            logger.error(f"Unexpected error calling Bedrock Embeddings: {e}")
            return []

def handler(event, context):
    request_id = context.aws_request_id
    logger.info(f"Received event", extra={
        "request_id": request_id,
        "record_count": len(event.get('Records', []))
    })
    
    oss_client = get_opensearch_client() if OPENSEARCH_HOST else None
    # Use DynamoDB client instead of resource
    table_name = TABLE_NAME
    processed_count = 0
    failed_count = 0

    for record in event['Records']:
        try:
            # Parse SQS message
            body = json.loads(record['body'])
            
            # Handle both direct S3 event (if testing) and EventBridge->SQS wrapped event
            if 'detail' in body and 'bucket' in body['detail']:
                bucket = body['detail']['bucket']['name']
                key = body['detail']['object']['key']
            elif 'Records' in body: # Direct S3 event
                bucket = body['Records'][0]['s3']['bucket']['name']
                key = body['Records'][0]['s3']['object']['key']
            else:
                logger.error("Unknown event structure", extra={
                    "request_id": request_id,
                    "record_body": str(record['body'])[:500]
                })
                failed_count += 1
                continue

            logger.info(f"Processing file", extra={
                "request_id": request_id,
                "bucket": bucket,
                "key": key
            })

            # 1. Extract Text
            logger.info("Extracting text content", extra={"request_id": request_id})
            text = extract_content(bucket, key)
            
            # 2. AI Processing
            logger.info("Starting AI processing", extra={"request_id": request_id})
            extracted_data = call_bedrock_extraction(text)
            vector = call_bedrock_embedding(text)
            
            doc_id = f"{bucket}/{key}"
            
            # Check for errors in AI processing
            if isinstance(extracted_data, dict) and "error" in extracted_data:
                logger.error(f"AI extraction failed", extra={
                    "request_id": request_id,
                    "error": extracted_data.get("error"),
                    "doc_id": doc_id
                })
                failed_count += 1
                continue
            
            if not vector:
                logger.error(f"AI embedding generation failed", extra={
                    "request_id": request_id,
                    "doc_id": doc_id
                })
                failed_count += 1
                continue
            
            # 3. Store Metadata in DynamoDB
            logger.info("Storing metadata in DynamoDB", extra={"request_id": request_id})
            item = {
                'docId': {'S': doc_id},
                'bucket': {'S': bucket},
                'key': {'S': key},
                'status': {'S': 'PROCESSED'},
                'metadata': {'S': json.dumps(extracted_data)}
            }
            dynamodb.put_item(TableName=table_name, Item=item)
            
            # 4. Store Vector in OpenSearch
            if oss_client and vector:
                logger.info("Storing vector in OpenSearch", extra={"request_id": request_id})
                document = {
                    'docId': doc_id,
                    'vector': vector,
                    'title': extracted_data.get('title', 'Unknown') if extracted_data else 'Unknown',
                    'summary': extracted_data.get('summary', '') if extracted_data else '',
                    'tags': extracted_data.get('tags', []) if extracted_data else []
                }
                # Create index if not exists (lazy init)
                index_name = "documents-index"
                if not oss_client.indices.exists(index=index_name):
                    logger.info("Creating OpenSearch index", extra={"request_id": request_id})
                    oss_client.indices.create(index=index_name, body={
                        "settings": {
                            "index.knn": True
                        },
                        "mappings": {
                            "properties": {
                                "vector": {
                                    "type": "knn_vector",
                                    "dimension": 1536,
                                    "method": {
                                        "name": "hnsw",
                                        "engine": "nmslib"
                                    }
                                }
                            }
                        }
                    })
                
                oss_client.index(index=index_name, body=document)

            # 5. Save Output to S3
            logger.info("Saving processed output to S3", extra={"request_id": request_id})
            output_key = f"{key}.json"
            s3.put_object(
                Bucket=PROCESSED_BUCKET,
                Key=output_key,
                Body=json.dumps(extracted_data)
            )
            
            processed_count += 1
            logger.info(f"Successfully processed file", extra={
                "request_id": request_id,
                "doc_id": doc_id
            })

        except Exception as e:
            logger.error(f"Failed to process record", extra={
                "request_id": request_id,
                "error": str(e),
                "error_type": type(e).__name__
            })
            failed_count += 1
            # In a real app, you might want to raise to trigger DLQ,
            # but for now we log and continue to process other records
            continue

    logger.info(f"Processing completed", extra={
        "request_id": request_id,
        "processed_count": processed_count,
        "failed_count": failed_count
    })
    
    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Processing complete",
            "processed": processed_count,
            "failed": failed_count
        })
    }
