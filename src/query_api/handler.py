import json
import os
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth

# Clients
bedrock = boto3.client('bedrock-runtime')

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
    """
    body = json.dumps({
        "inputText": text
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
    
    try:
        # Parse body
        body = json.loads(event.get('body', '{}'))
        query_text = body.get('query')
        
        if not query_text:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "Missing 'query' parameter"})
            }

        # 1. Generate Embedding for Query
        vector = call_bedrock_embedding(query_text)
        if not vector:
             return {
                "statusCode": 500,
                "body": json.dumps({"error": "Failed to generate embedding"})
            }

        # 2. Search OpenSearch
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

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"results": results})
        }

    except Exception as e:
        print(f"Error processing query: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
