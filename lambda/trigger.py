import json
import os
import time
import uuid
from pathlib import Path
from urllib.parse import unquote_plus

import boto3


VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".mkv", ".avi", ".webm"}

step_functions = boto3.client("stepfunctions")


def build_job_name(object_key: str) -> str:
    stem = Path(object_key).stem.lower()
    sanitized = "".join(char if char.isalnum() else "-" for char in stem).strip("-")
    sanitized = sanitized[:80] or "video"
    return f"{sanitized}-{int(time.time())}-{uuid.uuid4().hex[:8]}"


def lambda_handler(event, context):
    state_machine_arn = os.environ["STATE_MACHINE_ARN"]
    captions_bucket = os.environ["CAPTIONS_BUCKET"]
    output_prefix = os.environ.get("OUTPUT_PREFIX", "captions/").strip("/")

    started = []
    skipped = []

    for record in event.get("Records", []):
        if record.get("eventSource") != "aws:s3":
            continue

        bucket = record["s3"]["bucket"]["name"]
        raw_key = record["s3"]["object"]["key"]
        object_key = unquote_plus(raw_key)
        extension = Path(object_key).suffix.lower()

        if extension not in VIDEO_EXTENSIONS:
            skipped.append(object_key)
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

        step_functions.start_execution(
            stateMachineArn=state_machine_arn,
            name=execution_name,
            input=json.dumps(execution_input),
        )
        started.extend([english_job_name, hindi_job_name])

    return {
        "started_jobs": started,
        "skipped_objects": skipped,
    }