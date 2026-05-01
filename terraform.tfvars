aws_region                        = "ca-central-1"
project_name                      = "ccvideo"
input_bucket_name                 = "ccvideo-default-118922137804-input"
captions_bucket_name              = "ccvideo-default-118922137804-captions"
create_input_bucket               = false
create_captions_bucket            = false
create_step_functions_role        = false
create_state_machine              = true
existing_state_machine_arn        = "arn:aws:states:ca-central-1:118922137804:stateMachine:ccvideo-default-caption-pipeline"
existing_step_functions_role_name = "ccvideo-default-caption-pipeline-role"
create_lambda_role                = false
create_lambda_function            = true
existing_lambda_function_name     = "ccvideo-default-video-trigger"
existing_lambda_role_name         = "ccvideo-default-video-trigger-role"
notification_email                = null
output_prefix                     = "captions/"
enable_public_captions_read       = true
polling_wait_seconds              = 30
force_destroy                     = false

tags = {
  Application = "closed-caption-automation"
  Owner       = "platform-team"
}
