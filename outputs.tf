output "video_input_bucket_name" {
  description = "S3 bucket name where generated subtitle files are written."
  value       = local.video_input_bucket_name
}

output "captions_output_bucket_name" {
  description = "S3 bucket name where video uploads trigger caption generation."
  value       = local.captions_output_bucket_name
}

output "caption_pipeline_state_machine_arn" {
  description = "Step Functions state machine ARN orchestrating the caption workflow."
  value       = local.caption_pipeline_state_machine_arn
}

output "upload_trigger_lambda_name" {
  description = "Lambda function name invoked by S3 uploads."
  value       = local.video_ingest_trigger_lambda_name
}

output "notification_topic_arn" {
  description = "SNS topic ARN for pipeline success and failure notifications."
  value       = aws_sns_topic.caption_events.arn
}