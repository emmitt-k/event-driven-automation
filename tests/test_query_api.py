import os
import json
import pytest
from unittest.mock import MagicMock, patch

# Set env vars
os.environ['OPENSEARCH_HOST'] = 'https://test-opensearch.us-east-1.aoss.amazonaws.com'
os.environ['AWS_REGION'] = 'us-east-1'

from src.query_api import handler

@pytest.fixture
def mock_bedrock():
    with patch('src.query_api.handler.bedrock') as mock:
        mock.invoke_model.return_value = {
            'body': MagicMock(read=lambda: json.dumps({
                'embedding': [0.1, 0.2, 0.3]
            }).encode('utf-8'))
        }
        yield mock

@pytest.fixture
def mock_opensearch():
    with patch('src.query_api.handler.get_opensearch_client') as mock_get:
        mock_client = MagicMock()
        mock_get.return_value = mock_client
        
        # Mock Search Response
        mock_client.search.return_value = {
            'hits': {
                'hits': [
                    {
                        '_score': 0.9,
                        '_source': {
                            'docId': 'doc1',
                            'title': 'Result 1',
                            'summary': 'Summary 1',
                            'tags': ['tag1']
                        }
                    }
                ]
            }
        }
        yield mock_client

def test_query_api_success(mock_bedrock, mock_opensearch):
    event = {
        "body": json.dumps({"query": "test query"})
    }

    response = handler.handler(event, {})

    assert response['statusCode'] == 200
    body = json.loads(response['body'])
    assert len(body['results']) == 1
    assert body['results'][0]['title'] == 'Result 1'
    
    # Verify Bedrock called
    mock_bedrock.invoke_model.assert_called_once()
    
    # Verify OpenSearch called
    mock_opensearch.search.assert_called_once()
    call_args = mock_opensearch.search.call_args[1]
    assert call_args['index'] == 'documents-index'
    assert call_args['body']['query']['knn']['vector']['vector'] == [0.1, 0.2, 0.3]

def test_query_api_missing_param():
    event = {
        "body": json.dumps({})
    }
    response = handler.handler(event, {})
    assert response['statusCode'] == 400
