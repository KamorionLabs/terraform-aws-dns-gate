# -----------------------------------------------------------------------------
# Gate function (provided.al2023, arm64, binary "bootstrap")
# Serves the HTTP API (payload 2.0) and the scheduled maintenance task.
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

resource "aws_lambda_function" "this" {
  function_name = var.name
  description   = "dns-gate: security gateway in front of DNS provider APIs"
  role          = aws_iam_role.lambda.arn

  runtime       = "provided.al2023"
  architectures = ["arm64"]
  handler       = "bootstrap"
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  reserved_concurrent_executions = coalesce(var.lambda_reserved_concurrent_executions, -1)

  filename          = var.lambda_zip_path
  source_code_hash  = var.lambda_zip_path != null ? filebase64sha256(var.lambda_zip_path) : null
  s3_bucket         = var.lambda_s3_bucket
  s3_key            = var.lambda_s3_key
  s3_object_version = var.lambda_s3_object_version

  environment {
    variables = local.lambda_environment
  }

  dynamic "vpc_config" {
    for_each = local.lambda_in_vpc ? [1] : []
    content {
      subnet_ids         = var.lambda_vpc_subnet_ids
      security_group_ids = var.lambda_vpc_security_group_ids
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda.name
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy.lambda]

  lifecycle {
    precondition {
      condition     = (var.lambda_zip_path != null) != (var.lambda_s3_bucket != null && var.lambda_s3_key != null)
      error_message = "Set either lambda_zip_path or both lambda_s3_bucket and lambda_s3_key."
    }
    precondition {
      condition     = (var.config_yaml == null) != (var.config_uri == null)
      error_message = "Set either config_yaml or config_uri."
    }
    precondition {
      condition     = var.create_secret || var.secret_arn != null
      error_message = "create_secret = false requires secret_arn."
    }
    precondition {
      condition     = !local.lambda_in_vpc || length(var.lambda_vpc_security_group_ids) > 0
      error_message = "lambda_vpc_subnet_ids requires lambda_vpc_security_group_ids."
    }
  }
}

# Asynchronous invocations (maintenance schedule): no retry, the task is
# idempotent and the next run comes 5 minutes later. Runs must not stack.
resource "aws_lambda_function_event_invoke_config" "this" {
  function_name                = aws_lambda_function.this.function_name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 300
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*"
}
