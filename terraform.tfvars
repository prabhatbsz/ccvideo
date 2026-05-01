aws_region                  = "ca-central-1"
project_name                = "ccvideo"
input_bucket_name           = null
captions_bucket_name        = null
notification_email          = null
output_prefix               = "captions/"
enable_public_captions_read = true
polling_wait_seconds        = 30
force_destroy               = false

tags = {
  Application = "closed-caption-automation"
  Owner       = "platform-team"
}
