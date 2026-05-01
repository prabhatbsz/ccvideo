import json
import logging
import os
import time
import uuid
from pathlib import Path
from urllib.parse import unquote_plus

import boto3
from botocore.exceptions import ClientError


VIDEO_EXTENSIONS = {
    ".mp4",
    ".mov",
    ".m4v",
    ".mkv",
    ".avi",
    ".webm",
    ".mp3",
    ".wav",
    ".flac",
    ".m4a",
}

step_functions = boto3.client("stepfunctions")
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def build_job_name(object_key: str) -> str:
    stem = Path(object_key).stem.lower()
    sanitized = "".join(char if char.isalnum() else "-" for char in stem).strip("-")
    sanitized = sanitized[:80] or "video"
    return f"{sanitized}-{int(time.time())}-{uuid.uuid4().hex[:8]}"


def lambda_handler(event, context):
    state_machine_arn = os.environ["STATE_MACHINE_ARN"]
    captions_bucket = os.environ["CAPTIONS_BUCKET"]
    output_prefix = os.environ.get("OUTPUT_PREFIX", "captions/").strip("/")

    records = event.get("Records", [])
    logger.info("Received event with %d record(s)", len(records))
    print(f"Received event with {len(records)} record(s)")

    started = []
    skipped = []

    for record in records:
        if record.get("eventSource") != "aws:s3":
            logger.info("Skipping non-S3 event source: %s", record.get("eventSource"))
            print(f"Skipping non-S3 event source: {record.get('eventSource')}")
            continue

        bucket = record["s3"]["bucket"]["name"]
        raw_key = record["s3"]["object"]["key"]
        object_key = unquote_plus(raw_key)
        extension = Path(object_key).suffix.lower()

        logger.info("Processing object s3://%s/%s (extension=%s)", bucket, object_key, extension)
        print(f"Processing object s3://{bucket}/{object_key} (extension={extension})")

        if extension not in VIDEO_EXTENSIONS:
            skipped.append(object_key)
            logger.info("Skipping unsupported file type for key: %s", object_key)
            print(f"Skipping unsupported file type for key: {object_key}")
            continue

        job_base_name = build_job_name(object_key)
        english_job_name = f"{job_base_name}-en"
        hindi_job_name = f"{job_base_name}-hi"
        execution_name = f"exec-{job_base_name}"[:80]
        execution_input = {
            "job_name": job_base_name,
            "input_bucket": bucket,
            "input_key": object_key,
            "media_uri": f"s3://{bucket}/{object_key}",
            "captions_bucket": captions_bucket,
            "english_job_name": english_job_name,
            "hindi_job_name": hindi_job_name,
            "english_output_prefix": f"{output_prefix}/{job_base_name}/english/",
            "hindi_output_prefix": f"{output_prefix}/{job_base_name}/hindi/",
        }

        try:
            response = step_functions.start_execution(
                stateMachineArn=state_machine_arn,
                name=execution_name,
                input=json.dumps(execution_input),
            )
        except ClientError as exc:
            logger.exception("Failed to start Step Functions execution for %s", object_key)
            print(f"ERROR: Failed to start Step Functions execution for {object_key}: {exc}")
            raise

        logger.info(
            "Started Step Functions execution '%s' for object s3://%s/%s",
            execution_name,
            bucket,
            object_key,
        )
        print(
            "Started Step Functions execution "
            f"'{execution_name}' for object s3://{bucket}/{object_key}; "
            f"executionArn={response.get('executionArn', 'n/a')}"
        )
        started.extend([english_job_name, hindi_job_name])

    logger.info("Lambda processing summary: started_jobs=%s skipped_objects=%s", started, skipped)
    print(f"Lambda processing summary: started_jobs={started} skipped_objects={skipped}")

    return {
        "started_jobs": started,
        "skipped_objects": skipped,
    }