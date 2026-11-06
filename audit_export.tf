# -----------------------------------------------------------------------------
# Audit export (optional): subscription filter on the function log group that
# forwards the audit lines ({ $.type = "audit" }) to Firehose, Kinesis, a
# Lambda function or a CloudWatch Logs destination.
# -----------------------------------------------------------------------------

locals {
  audit_export          = var.audit_export != null
  audit_export_service  = local.audit_export ? split(":", var.audit_export.destination_arn)[2] : ""
  audit_export_new_role = local.audit_export ? contains(["firehose", "kinesis"], local.audit_export_service) && var.audit_export.role_arn == null : false
  audit_export_role_arn = local.audit_export_new_role ? aws_iam_role.audit_export[0].arn : local.audit_export ? var.audit_export.role_arn : null
  audit_export_arn      = local.audit_export ? split(":", var.audit_export.destination_arn) : []
  audit_export_region   = local.audit_export ? local.audit_export_arn[3] : ""
  audit_export_account  = local.audit_export ? local.audit_export_arn[4] : ""
}

data "aws_iam_policy_document" "audit_export_assume" {
  count = local.audit_export_new_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["logs.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_log_group.lambda.arn, "${aws_cloudwatch_log_group.lambda.arn}:*"]
    }
  }
}

resource "aws_iam_role" "audit_export" {
  count = local.audit_export_new_role ? 1 : 0

  name                 = "${var.name}-audit-export"
  description          = "CloudWatch Logs delivery of the dns-gate audit events (${var.name})"
  assume_role_policy   = data.aws_iam_policy_document.audit_export_assume[0].json
  permissions_boundary = var.iam_permissions_boundary_arn

  tags = var.tags
}

data "aws_iam_policy_document" "audit_export" {
  count = local.audit_export_new_role ? 1 : 0

  statement {
    sid       = "Deliver"
    actions   = local.audit_export_service == "firehose" ? ["firehose:PutRecord", "firehose:PutRecordBatch"] : ["kinesis:PutRecord", "kinesis:PutRecords"]
    resources = [var.audit_export.destination_arn]
  }

  dynamic "statement" {
    for_each = var.audit_export.kms_key_arn != null ? [var.audit_export.kms_key_arn] : []
    content {
      sid       = "EncryptedDestination"
      actions   = ["kms:GenerateDataKey"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "audit_export" {
  count = local.audit_export_new_role ? 1 : 0

  name   = "deliver"
  role   = aws_iam_role.audit_export[0].id
  policy = data.aws_iam_policy_document.audit_export[0].json
}

resource "aws_lambda_permission" "audit_export" {
  count = local.audit_export && local.audit_export_service == "lambda" ? 1 : 0

  statement_id   = "AllowDnsGateAudit-${var.name}"
  action         = "lambda:InvokeFunction"
  function_name  = var.audit_export.destination_arn
  principal      = "logs.amazonaws.com"
  source_arn     = "${aws_cloudwatch_log_group.lambda.arn}:*"
  source_account = local.account_id
}

resource "aws_cloudwatch_log_subscription_filter" "audit_export" {
  count = local.audit_export ? 1 : 0

  name            = coalesce(var.audit_export.filter_name, "${var.name}-audit")
  log_group_name  = aws_cloudwatch_log_group.lambda.name
  filter_pattern  = var.audit_export.filter_pattern
  destination_arn = var.audit_export.destination_arn
  role_arn        = local.audit_export_role_arn
  distribution    = local.audit_export_service == "kinesis" ? var.audit_export.distribution : null

  depends_on = [aws_iam_role_policy.audit_export, aws_lambda_permission.audit_export]

  lifecycle {
    precondition {
      condition     = local.audit_export_region == local.region
      error_message = "audit_export.destination_arn must be in the region of the function (${local.region}): subscription filters do not deliver across regions."
    }
    precondition {
      condition     = local.audit_export_service == "logs" || local.audit_export_account == local.account_id
      error_message = "audit_export.destination_arn must be in the account of the function (${local.account_id}); use a CloudWatch Logs destination for another account."
    }
  }
}
