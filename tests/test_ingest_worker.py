import os
import json
import pytest
import boto3
from moto import mock_aws
from unittest.mock import MagicMock, patch

# Set env vars before importing handler
os.environ['PROCESSED_BUCKET'] = 'processed-bucket'
os.environ['DYNAMODB_TABLE'] = 'documents-table'
os.environ['OPENSEARCH_HOST'] = 'https://test-opensearch.us-east-1.aoss.amazonaws.com'
os.environ['AWS_REGION'] = 'us-east-1'

from src.ingest_worker import handler

@pytest.fixture
def s3_setup():
    with mock_aws():
        s3 = boto3.client('s3', region_name='us-east-1')
        s3.create_bucket(Bucket='raw-input')
        s3.create_bucket(Bucket='processed-bucket')
        yield s3

@pytest.fixture
def dynamodb_setup():
    with mock_aws():
        dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
        dynamodb.create_table(
            TableName='documents-table',
            KeySchema=[{'AttributeName': 'docId', 'KeyType': 'HASH'}],
            AttributeDefinitions=[{'AttributeName': 'docId', 'AttributeType': 'S'}],
            BillingMode='PAY_PER_REQUEST'
        )
        yield dynamodb

@pytest.fixture
def mock_bedrock():
    with patch('src.ingest_worker.handler.bedrock') as mock:
        # Mock Extraction
        mock.invoke_model.return_value = {
            'body': MagicMock(read=lambda: json.dumps({
                'content': [{'text': '{"title": "Test Doc", "summary": "A test", "tags": ["test"], "date": "2023-01-01"}'}],
                'embedding': [0.1, 0.2, 0.3] # For Titan
            }).encode('utf-8'))
        }
        yield mock

@pytest.fixture
def mock_opensearch():
    with patch('src.ingest_worker.handler.get_opensearch_client') as mock_get:
        mock_client = MagicMock()
        mock_get.return_value = mock_client
        # Mock index exists check to return False first (to trigger create), then True
        mock_client.indices.exists.return_value = False
        yield mock_client

def test_ingest_worker_success(s3_setup, dynamodb_setup, mock_bedrock, mock_opensearch):
    # Patch the global clients in the handler module to use our moto-mocked clients
    with patch('src.ingest_worker.handler.s3', s3_setup), \
         patch('src.ingest_worker.handler.dynamodb', dynamodb_setup):
        
        # 1. Upload file to S3
        s3_setup.put_object(Bucket='raw-input', Key='test.txt', Body='This is a test document.')

        # 2. Create SQS Event
        event = {
            "Records": [
                {
                    "body": json.dumps({
                        "detail": {
                            "bucket": {"name": "raw-input"},
                            "object": {"key": "test.txt"}
                        }
                    })
                }
            ]
        }

        # 3. Run Handler
        response = handler.handler(event, {})

        # 4. Verify
        assert response['statusCode'] == 200

        # Verify DynamoDB
        table = dynamodb_setup.Table('documents-table')
        item = table.get_item(Key={'docId': 'raw-input/test.txt'})['Item']
        assert item['status'] == 'PROCESSED'
        assert item['metadata']['title'] == 'Test Doc'

        # Verify S3 Output
        obj = s3_setup.get_object(Bucket='processed-bucket', Key='test.txt.json')
        content = json.loads(obj['Body'].read().decode('utf-8'))
        assert content['title'] == 'Test Doc'

        # Verify OpenSearch Call
        mock_opensearch.index.assert_called_once()
        call_args = mock_opensearch.index.call_args[1]
        assert call_args['index'] == 'documents-index'
        assert call_args['body']['docId'] == 'raw-input/test.txt'
        assert call_args['body']['title'] == 'Test Doc'
