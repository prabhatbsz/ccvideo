variable "bucket_name" {
  description = "Private S3 bucket name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to the bucket"
  type        = map(string)
  default     = {}
}
