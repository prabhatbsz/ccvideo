variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "ca-central-1"
}

variable "project_name" {
  description = "Prefix used for resource naming."
  type        = string
  default     = "ccvideo"
}

variable "input_bucket_name" {
  description = "Optional custom S3 bucket name for uploaded videos. Leave null to auto-generate a globally unique name."
  type        = string
  default     = null
}

variable "captions_bucket_name" {
  description = "Optional custom S3 bucket name for generated caption files. Leave null to auto-generate a globally unique name."
  type        = string
  default     = null
}

variable "notification_email" {
  description = "Optional email address to receive SNS notifications for success and failure events."
  type        = string
  default     = null
}

variable "output_prefix" {
  description = "S3 prefix inside the captions bucket where Amazon Transcribe writes subtitle output."
  type        = string
  default     = "captions/"
}

variable "enable_public_captions_read" {
  description = "Allow public read access to generated caption files in the captions bucket. Set to false later to make captions private again."
  type        = bool
  default     = false
}

variable "polling_wait_seconds" {
  description = "Delay between Step Functions polling attempts while waiting for Amazon Transcribe to finish."
  type        = number
  default     = 30
}

variable "force_destroy" {
  description = "Allow Terraform to delete non-empty S3 buckets during destroy."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags applied to all supported resources."
  type        = map(string)
  default     = {}
}
