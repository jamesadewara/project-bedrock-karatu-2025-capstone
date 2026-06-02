# ============================================================
# LAMBDA FUNCTION - bedrock-asset-processor
# Triggered by S3 upload events
# Logs filename to CloudWatch
# ============================================================
import json
import boto3
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process S3 object creation events.
    Logs the uploaded filename to CloudWatch.
    """
    try:
        # Extract S3 event details
        for record in event.get('Records', []):
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            size = record['s3']['object'].get('size', 0)
            event_time = record.get('eventTime', 'unknown')

            # Log the required message
            log_message = f"Image received: {key}"
            logger.info(log_message)

            # Additional structured logging
            logger.info(json.dumps({
                'event': 's3_object_uploaded',
                'bucket': bucket,
                'key': key,
                'size': size,
                'event_time': event_time,
                'message': log_message
            }))

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Asset processed successfully',
                'processed_files': len(event.get('Records', []))
            })
        }

    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
