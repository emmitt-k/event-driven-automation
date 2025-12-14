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
bedrock = boto3.client('bedrock-runtime', config=retry_config)

# Config
OPENSEARCH_HOST = os.environ.get('OPENSEARCH_HOST')
REGION = os.environ.get('AWS_REGION', 'us-east-1')

# OpenSearch Client Setup
def get_opensearch_client():
    credentials = boto3.Session().get_credentials()
    auth = AWSV4SignerAuth(credentials, REGION, 'aoss')
    
    host = OPENSEARCH_HOST.replace("https://", "") if OPENSEARCH_HOST else ""

    return OpenSearch(
        hosts=[{'host': host, 'port': 443}],
        http_auth=auth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
        pool_maxsize=20
    )

def call_bedrock_embedding(text):
    """
    Call Titan Embeddings to generate vector for the query.
    Implements retry logic with exponential backoff.
    """
    body = json.dumps({
        "inputText": text
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

def validate_input(body):
    """
    Validate input parameters for the query API.
    """
    if not isinstance(body, dict):
        raise ValueError("Request body must be a valid JSON object")
    
    query_text = body.get('query')
    if not query_text:
        raise ValueError("Missing 'query' parameter")
    
    if not isinstance(query_text, str):
        raise ValueError("'query' parameter must be a string")
    
    if len(query_text.strip()) == 0:
        raise ValueError("'query' parameter cannot be empty")
    
    if len(query_text) > 8000:  # Titan limit
        raise ValueError("'query' parameter exceeds maximum length of 8000 characters")
    
    return query_text.strip()

def handler(event, context):
    request_id = context.aws_request_id
    logger.info(f"Received event", extra={
        "request_id": request_id,
        "event": json.dumps(event)
    })
    
    try:
        # Parse body
        try:
            body = json.loads(event.get('body', '{}'))
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in request body", extra={
                "request_id": request_id,
                "error": str(e)
            })
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Invalid JSON in request body"})
            }
        
        # Validate input
        try:
            query_text = validate_input(body)
            logger.info(f"Input validation successful", extra={
                "request_id": request_id,
                "query_length": len(query_text)
            })
        except ValueError as e:
            logger.warning(f"Input validation failed", extra={
                "request_id": request_id,
                "error": str(e)
            })
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": str(e)})
            }

        # 1. Generate Embedding for Query
        logger.info("Generating embedding for query", extra={"request_id": request_id})
        vector = call_bedrock_embedding(query_text)
        if not vector:
            logger.error("Failed to generate embedding", extra={"request_id": request_id})
            return {
                "statusCode": 500,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Failed to generate embedding"})
            }

        # 2. Search OpenSearch
        logger.info("Searching OpenSearch", extra={"request_id": request_id})
        try:
            oss_client = get_opensearch_client()
            index_name = "documents-index"
            
            query = {
                "size": 5,
                "query": {
                    "knn": {
                        "vector": {
                            "vector": vector,
                            "k": 5
                        }
                    }
                }
            }
            
            response = oss_client.search(index=index_name, body=query)
            logger.info("OpenSearch search successful", extra={
                "request_id": request_id,
                "hits_count": len(response['hits']['hits'])
            })
        except Exception as e:
            logger.error(f"OpenSearch search failed", extra={
                "request_id": request_id,
                "error": str(e)
            })
            return {
                "statusCode": 500,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Search service unavailable"})
            }
        
        # 3. Format Results
        hits = response['hits']['hits']
        results = []
        for hit in hits:
            source = hit['_source']
            results.append({
                "score": hit['_score'],
                "docId": source.get('docId'),
                "title": source.get('title'),
                "summary": source.get('summary'),
                "tags": source.get('tags')
            })

        logger.info("Query processed successfully", extra={
            "request_id": request_id,
            "results_count": len(results)
        })
        
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"results": results})
        }

    except Exception as e:
        logger.error(f"Unexpected error processing query", extra={
            "request_id": request_id,
            "error": str(e),
            "error_type": type(e).__name__
        })
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Internal server error"})
        }
