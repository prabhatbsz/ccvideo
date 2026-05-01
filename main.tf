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
      "${aws_s3_bucket.captions_output.arn}/*"
    ]
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

  input_bucket_name    = coalesce(var.input_bucket_name, lower("${local.name_prefix}-${data.aws_caller_identity.current.account_id}-input"))
  captions_bucket_name = coalesce(var.captions_bucket_name, lower("${local.name_prefix}-${data.aws_caller_identity.current.account_id}-captions"))
  sns_topic_name       = "${local.name_prefix}-caption-events"
  lambda_name          = "${local.name_prefix}-video-trigger"
  step_function_name   = "${local.name_prefix}-caption-pipeline"
}

resource "aws_s3_bucket" "video_input" {
  bucket        = local.input_bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.default_tags, {
    Name = local.input_bucket_name
    Role = "video-input"
  })
}

resource "aws_s3_bucket" "captions_output" {
  bucket        = local.captions_bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.default_tags, {
    Name = local.captions_bucket_name
    Role = "caption-output"
  })
}

resource "aws_s3_bucket_versioning" "video_input" {
  bucket = aws_s3_bucket.video_input.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "captions_output" {
  bucket = aws_s3_bucket.captions_output.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "video_input" {
  bucket = aws_s3_bucket.video_input.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "captions_output" {
  bucket = aws_s3_bucket.captions_output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "video_input" {
  bucket = aws_s3_bucket.video_input.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "captions_output" {
  bucket = aws_s3_bucket.captions_output.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "captions_output_public_read" {
  count = var.enable_public_captions_read ? 1 : 0

  bucket = aws_s3_bucket.captions_output.id
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
  name               = "${local.step_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.step_functions_assume_role.json

  tags = local.default_tags
}

resource "aws_iam_role_policy" "step_functions" {
  name = "${local.step_function_name}-policy"
  role = aws_iam_role.step_functions.id

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
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.caption_events.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "caption_pipeline" {
  name     = local.step_function_name
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "Automated caption generation workflow for uploaded videos"
    StartAt = "StartTranscriptionJob"
    States = {
      StartTranscriptionJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:transcribe:startTranscriptionJob"
        Parameters = {
          "TranscriptionJobName.$" = "$.job_name"
          Media = {
            "MediaFileUri.$" = "$.media_uri"
          }
          IdentifyLanguage     = true
          "OutputBucketName.$" = "$.captions_bucket"
          "OutputKey.$"        = "$.output_prefix"
          Subtitles = {
            Formats = ["srt", "vtt"]
          }
        }
        Next = "WaitForTranscription"
      }
      WaitForTranscription = {
        Type    = "Wait"
        Seconds = var.polling_wait_seconds
        Next    = "GetTranscriptionJob"
      }
      GetTranscriptionJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:transcribe:getTranscriptionJob"
        Parameters = {
          "TranscriptionJobName.$" = "$.job_name"
        }
        ResultPath = "$.job_details"
        Next       = "CheckTranscriptionStatus"
      }
      CheckTranscriptionStatus = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.job_details.TranscriptionJob.TranscriptionJobStatus"
            StringEquals = "COMPLETED"
            Next         = "PublishSuccess"
          },
          {
            Variable     = "$.job_details.TranscriptionJob.TranscriptionJobStatus"
            StringEquals = "FAILED"
            Next         = "PublishFailure"
          }
        ]
        Default = "WaitForTranscription"
      }
      PublishSuccess = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.caption_events.arn
          Subject     = "Caption generation completed"
          "Message.$" = "States.Format('Closed captions are ready for s3://{}/{}. Output bucket: s3://{}/{}', $.input_bucket, $.input_key, $.captions_bucket, $.output_prefix)"
        }
        End = true
      }
      PublishFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.caption_events.arn
          Subject     = "Caption generation failed"
          "Message.$" = "States.Format('Caption generation failed for s3://{}/{}: {}', $.input_bucket, $.input_key, $.job_details.TranscriptionJob.FailureReason)"
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

resource "aws_iam_role" "lambda" {
  name               = "${local.lambda_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.default_tags
}

resource "aws_iam_role_policy" "lambda" {
  name = "${local.lambda_name}-policy"
  role = aws_iam_role.lambda.id

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
        Resource = aws_sfn_state_machine.caption_pipeline.arn
      }
    ]
  })
}

resource "aws_lambda_function" "video_ingest_trigger" {
  function_name    = local.lambda_name
  role             = aws_iam_role.lambda.arn
  handler          = "trigger.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.caption_pipeline.arn
      CAPTIONS_BUCKET   = aws_s3_bucket.captions_output.bucket
      OUTPUT_PREFIX     = var.output_prefix
    }
  }

  tags = local.default_tags
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.video_ingest_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.video_input.arn
}

resource "aws_s3_bucket_notification" "video_uploads" {
  bucket = aws_s3_bucket.video_input.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.video_ingest_trigger.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
