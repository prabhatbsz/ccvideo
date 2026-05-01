data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "step_functions_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "captions_public_read" {
  count = var.enable_public_captions_read ? 1 : 0

  statement {
    sid    = "AllowPublicReadOfCaptions"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:GetObject"]

    resources = [
      "${local.captions_output_bucket_arn}/*"
    ]
  }
}

data "aws_iam_policy_document" "transcribe_output_bucket" {
  statement {
    sid    = "AllowTranscribeGetObject"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["transcribe.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${local.captions_output_bucket_arn}/*"]
  }

  statement {
    sid    = "AllowTranscribePutObject"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["transcribe.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${local.video_input_bucket_arn}/*"]
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/trigger.py"
  output_path = "${path.module}/lambda/trigger.zip"
}

locals {
  name_prefix = "${var.project_name}-${terraform.workspace}"

  default_tags = merge(
    {
      Project     = var.project_name
      Environment = terraform.workspace
      ManagedBy   = "Terraform"
    },
    var.tags
  )

  input_bucket_name        = coalesce(var.input_bucket_name, lower("${local.name_prefix}-${data.aws_caller_identity.current.account_id}-input"))
  captions_bucket_name     = coalesce(var.captions_bucket_name, lower("${local.name_prefix}-${data.aws_caller_identity.current.account_id}-captions"))
  sns_topic_name           = "${local.name_prefix}-caption-events"
  lambda_name              = "${local.name_prefix}-video-trigger"
  lambda_function_name     = coalesce(var.existing_lambda_function_name, "${local.name_prefix}-video-trigger")
  step_function_name       = "${local.name_prefix}-caption-pipeline"
  step_functions_role_name = coalesce(var.existing_step_functions_role_name, "${local.step_function_name}-role")
  lambda_role_name         = coalesce(var.existing_lambda_role_name, "${local.lambda_name}-role")
  state_machine_arn        = coalesce(var.existing_state_machine_arn, "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${local.step_function_name}")
  lambda_function_arn      = coalesce(var.existing_lambda_function_arn, "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${local.lambda_function_name}")
}

resource "aws_s3_bucket" "video_input" {
  count         = var.create_input_bucket ? 1 : 0
  bucket        = local.input_bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.default_tags, {
    Name = local.input_bucket_name
    Role = "video-input"
  })
}

resource "aws_s3_bucket" "captions_output" {
  count         = var.create_captions_bucket ? 1 : 0
  bucket        = local.captions_bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.default_tags, {
    Name = local.captions_bucket_name
    Role = "caption-output"
  })
}

data "aws_s3_bucket" "video_input_existing" {
  count  = var.create_input_bucket ? 0 : 1
  bucket = local.input_bucket_name
}

data "aws_s3_bucket" "captions_output_existing" {
  count  = var.create_captions_bucket ? 0 : 1
  bucket = local.captions_bucket_name
}

locals {
  video_input_bucket_id   = var.create_input_bucket ? aws_s3_bucket.video_input[0].id : data.aws_s3_bucket.video_input_existing[0].id
  video_input_bucket_arn  = var.create_input_bucket ? aws_s3_bucket.video_input[0].arn : data.aws_s3_bucket.video_input_existing[0].arn
  video_input_bucket_name = var.create_input_bucket ? aws_s3_bucket.video_input[0].bucket : data.aws_s3_bucket.video_input_existing[0].bucket

  captions_output_bucket_id   = var.create_captions_bucket ? aws_s3_bucket.captions_output[0].id : data.aws_s3_bucket.captions_output_existing[0].id
  captions_output_bucket_arn  = var.create_captions_bucket ? aws_s3_bucket.captions_output[0].arn : data.aws_s3_bucket.captions_output_existing[0].arn
  captions_output_bucket_name = var.create_captions_bucket ? aws_s3_bucket.captions_output[0].bucket : data.aws_s3_bucket.captions_output_existing[0].bucket
}

resource "aws_s3_bucket_versioning" "video_input" {
  bucket = local.video_input_bucket_id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_versioning" "captions_output" {
  bucket = local.captions_output_bucket_id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "video_input" {
  bucket = local.video_input_bucket_id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "captions_output" {
  bucket = local.captions_output_bucket_id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "video_input" {
  bucket = local.video_input_bucket_id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "transcribe_output" {
  bucket = local.video_input_bucket_id
  policy = data.aws_iam_policy_document.transcribe_output_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.video_input]
}

resource "aws_s3_bucket_public_access_block" "captions_output" {
  bucket = local.captions_output_bucket_id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "captions_output_public_read" {
  count = var.enable_public_captions_read ? 1 : 0

  bucket = local.captions_output_bucket_id
  policy = data.aws_iam_policy_document.captions_public_read[0].json

  depends_on = [aws_s3_bucket_public_access_block.captions_output]
}

resource "aws_sns_topic" "caption_events" {
  name = local.sns_topic_name

  tags = merge(local.default_tags, {
    Name = local.sns_topic_name
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email == null ? 0 : 1

  topic_arn = aws_sns_topic.caption_events.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_iam_role" "step_functions" {
  count              = var.create_step_functions_role ? 1 : 0
  name               = local.step_functions_role_name
  assume_role_policy = data.aws_iam_policy_document.step_functions_assume_role.json

  tags = local.default_tags
}

data "aws_iam_role" "step_functions_existing" {
  count = var.create_step_functions_role ? 0 : 1
  name  = local.step_functions_role_name
}

locals {
  step_functions_role_arn = var.create_step_functions_role ? aws_iam_role.step_functions[0].arn : data.aws_iam_role.step_functions_existing[0].arn
}

resource "aws_iam_role_policy" "step_functions" {
  name = "${local.step_function_name}-policy"
  role = local.step_functions_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "transcribe:StartTranscriptionJob",
          "transcribe:GetTranscriptionJob"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${local.captions_output_bucket_arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${local.video_input_bucket_arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.caption_events.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "caption_pipeline" {
  count    = var.create_state_machine ? 1 : 0
  name     = local.step_function_name
  role_arn = local.step_functions_role_arn

  definition = jsonencode({
    Comment = "Automated caption generation workflow for uploaded videos"
    StartAt = "RunLanguageJobs"
    States = {
      RunLanguageJobs = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "StartEnglishTranscription"
            States = {
              StartEnglishTranscription = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:transcribe:startTranscriptionJob"
                Parameters = {
                  "TranscriptionJobName.$" = "$.english_job_name"
                  Media = {
                    "MediaFileUri.$" = "$.media_uri"
                  }
                  LanguageCode         = "en-US"
                  "OutputBucketName.$" = "$.captions_bucket"
                  "OutputKey.$"        = "$.english_output_prefix"
                  Subtitles = {
                    Formats = ["srt", "vtt"]
                  }
                }
                Next = "WaitForEnglishTranscription"
              }
              WaitForEnglishTranscription = {
                Type    = "Wait"
                Seconds = var.polling_wait_seconds
                Next    = "GetEnglishTranscription"
              }
              GetEnglishTranscription = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:transcribe:getTranscriptionJob"
                Parameters = {
                  "TranscriptionJobName.$" = "$.english_job_name"
                }
                ResultPath = "$.english_job_details"
                Next       = "CheckEnglishStatus"
              }
              CheckEnglishStatus = {
                Type = "Choice"
                Choices = [
                  {
                    Variable     = "$.english_job_details.TranscriptionJob.TranscriptionJobStatus"
                    StringEquals = "COMPLETED"
                    Next         = "EnglishCompleted"
                  },
                  {
                    Variable     = "$.english_job_details.TranscriptionJob.TranscriptionJobStatus"
                    StringEquals = "FAILED"
                    Next         = "EnglishFailed"
                  }
                ]
                Default = "WaitForEnglishTranscription"
              }
              EnglishCompleted = {
                Type = "Succeed"
              }
              EnglishFailed = {
                Type  = "Fail"
                Error = "EnglishTranscriptionFailed"
              }
            }
          },
          {
            StartAt = "StartHindiTranscription"
            States = {
              StartHindiTranscription = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:transcribe:startTranscriptionJob"
                Parameters = {
                  "TranscriptionJobName.$" = "$.hindi_job_name"
                  Media = {
                    "MediaFileUri.$" = "$.media_uri"
                  }
                  LanguageCode         = "hi-IN"
                  "OutputBucketName.$" = "$.captions_bucket"
                  "OutputKey.$"        = "$.hindi_output_prefix"
                  Subtitles = {
                    Formats = ["srt", "vtt"]
                  }
                }
                Next = "WaitForHindiTranscription"
              }
              WaitForHindiTranscription = {
                Type    = "Wait"
                Seconds = var.polling_wait_seconds
                Next    = "GetHindiTranscription"
              }
              GetHindiTranscription = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:transcribe:getTranscriptionJob"
                Parameters = {
                  "TranscriptionJobName.$" = "$.hindi_job_name"
                }
                ResultPath = "$.hindi_job_details"
                Next       = "CheckHindiStatus"
              }
              CheckHindiStatus = {
                Type = "Choice"
                Choices = [
                  {
                    Variable     = "$.hindi_job_details.TranscriptionJob.TranscriptionJobStatus"
                    StringEquals = "COMPLETED"
                    Next         = "HindiCompleted"
                  },
                  {
                    Variable     = "$.hindi_job_details.TranscriptionJob.TranscriptionJobStatus"
                    StringEquals = "FAILED"
                    Next         = "HindiFailed"
                  }
                ]
                Default = "WaitForHindiTranscription"
              }
              HindiCompleted = {
                Type = "Succeed"
              }
              HindiFailed = {
                Type  = "Fail"
                Error = "HindiTranscriptionFailed"
              }
            }
          }
        ]
        Next = "PublishSuccess"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error_info"
            Next        = "PublishFailure"
          }
        ]
      }
      PublishSuccess = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.caption_events.arn
          Subject     = "Caption generation completed (English + Hindi)"
          "Message.$" = "States.Format('Closed captions are ready for s3://{}/{}. Output bucket: s3://{}. English path: {} Hindi path: {}', $.input_bucket, $.input_key, $.captions_bucket, $.english_output_prefix, $.hindi_output_prefix)"
        }
        End = true
      }
      PublishFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.caption_events.arn
          Subject     = "Caption generation failed"
          "Message.$" = "States.Format('Caption generation failed for s3://{}/{}: {}', $.input_bucket, $.input_key, $.error_info.Cause)"
        }
        Next = "WorkflowFailed"
      }
      WorkflowFailed = {
        Type  = "Fail"
        Error = "TranscriptionFailed"
      }
    }
  })

  tags = local.default_tags
}

locals {
  caption_pipeline_state_machine_arn = var.create_state_machine ? aws_sfn_state_machine.caption_pipeline[0].arn : local.state_machine_arn
}

resource "aws_iam_role" "lambda" {
  count              = var.create_lambda_role ? 1 : 0
  name               = local.lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.default_tags
}

data "aws_iam_role" "lambda_existing" {
  count = var.create_lambda_role ? 0 : 1
  name  = local.lambda_role_name
}

locals {
  lambda_role_arn = var.create_lambda_role ? aws_iam_role.lambda[0].arn : data.aws_iam_role.lambda_existing[0].arn
}

resource "aws_iam_role_policy" "lambda" {
  name = "${local.lambda_name}-policy"
  role = local.lambda_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = local.caption_pipeline_state_machine_arn
      }
    ]
  })
}

resource "aws_lambda_function" "video_ingest_trigger" {
  count            = var.create_lambda_function ? 1 : 0
  function_name    = local.lambda_function_name
  role             = local.lambda_role_arn
  handler          = "trigger.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      STATE_MACHINE_ARN = local.caption_pipeline_state_machine_arn
      CAPTIONS_BUCKET   = local.video_input_bucket_name
      OUTPUT_PREFIX     = var.output_prefix
    }
  }

  tags = local.default_tags
}

locals {
  video_ingest_trigger_lambda_name = var.create_lambda_function ? aws_lambda_function.video_ingest_trigger[0].function_name : local.lambda_function_name
  video_ingest_trigger_lambda_arn  = var.create_lambda_function ? aws_lambda_function.video_ingest_trigger[0].arn : local.lambda_function_arn
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id_prefix = "AllowExecutionFromS3-"
  action              = "lambda:InvokeFunction"
  function_name       = local.video_ingest_trigger_lambda_name
  principal           = "s3.amazonaws.com"
  source_arn          = local.captions_output_bucket_arn
}

resource "aws_s3_bucket_notification" "video_uploads" {
  bucket = local.captions_output_bucket_id

  lambda_function {
    lambda_function_arn = local.video_ingest_trigger_lambda_arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
