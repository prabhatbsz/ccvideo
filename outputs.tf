output "video_input_bucket_name" {
  description = "S3 bucket name where videos must be uploaded to trigger caption generation."
  value       = aws_s3_bucket.video_input.bucket
}

output "captions_output_bucket_name" {
  description = "S3 bucket name where Amazon Transcribe stores the generated subtitle files."
  value       = aws_s3_bucket.captions_output.bucket
}

output "caption_pipeline_state_machine_arn" {
  description = "Step Functions state machine ARN orchestrating the caption workflow."
  value       = aws_sfn_state_machine.caption_pipeline.arn
}

output "upload_trigger_lambda_name" {
  description = "Lambda function name invoked by S3 uploads."
  value       = aws_lambda_function.video_ingest_trigger.function_name
}

output "notification_topic_arn" {
  description = "SNS topic ARN for pipeline success and failure notifications."
  value       = aws_sns_topic.caption_events.arn
}