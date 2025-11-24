import json
import os
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth
from botocore.exceptions import ClientError

# Clients
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
bedrock = boto3.client('bedrock-runtime')

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

    try:
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
            return json.loads(content[start:end])
        return {}
    except Exception as e:
        print(f"Error calling Bedrock Extraction: {e}")
        return {"error": str(e)}

def call_bedrock_embedding(text):
    """
    Call Titan Embeddings to generate vector.
    """
    body = json.dumps({
        "inputText": text[:8000] # Titan limit
    })
    
    try:
        response = bedrock.invoke_model(
            modelId='amazon.titan-embed-text-v1',
            body=body
        )
        response_body = json.loads(response['body'].read())
        return response_body['embedding']
    except Exception as e:
        print(f"Error calling Bedrock Embeddings: {e}")
        return []

def handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    oss_client = get_opensearch_client() if OPENSEARCH_HOST else None
    table = dynamodb.Table(TABLE_NAME)

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
                print("Unknown event structure")
                continue

            print(f"Processing {bucket}/{key}")

            # 1. Extract Text
            text = extract_content(bucket, key)
            
            # 2. AI Processing
            extracted_data = call_bedrock_extraction(text)
            vector = call_bedrock_embedding(text)
            
            doc_id = f"{bucket}/{key}"
            
            # 3. Store Metadata in DynamoDB
            item = {
                'docId': doc_id,
                'bucket': bucket,
                'key': key,
                'status': 'PROCESSED',
                'metadata': extracted_data
            }
            table.put_item(Item=item)
            
            # 4. Store Vector in OpenSearch
            if oss_client and vector:
                document = {
                    'docId': doc_id,
                    'vector': vector,
                    'title': extracted_data.get('title', 'Unknown'),
                    'summary': extracted_data.get('summary', ''),
                    'tags': extracted_data.get('tags', [])
                }
                # Create index if not exists (lazy init)
                index_name = "documents-index"
                if not oss_client.indices.exists(index=index_name):
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
            output_key = f"{key}.json"
            s3.put_object(
                Bucket=PROCESSED_BUCKET,
                Key=output_key,
                Body=json.dumps(extracted_data)
            )
            
            print(f"Successfully processed {key}")

        except Exception as e:
            print(f"Failed to process record: {e}")
            # In a real app, you might want to raise to trigger DLQ, 
            # but for now we log and continue to process other records
            continue

    return {"statusCode": 200, "body": "Processing complete"}
