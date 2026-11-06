# -----------------------------------------------------------------------------
# Lambda execution role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name                 = "${var.name}-lambda"
  description          = "dns-gate Lambda execution role (${var.name})"
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume.json
  permissions_boundary = var.iam_permissions_boundary_arn

  tags = var.tags
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid = "Store"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:ConditionCheckItem",
    ]
    resources = [
      aws_dynamodb_table.this.arn,
      "${aws_dynamodb_table.this.arn}/index/*",
    ]
  }

  dynamic "statement" {
    for_each = var.dynamodb_kms_key_arn != null ? [1] : []
    content {
      sid       = "StoreKms"
      actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
      resources = [var.dynamodb_kms_key_arn]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["dynamodb.${local.region}.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.has_secret ? [1] : []
    content {
      sid       = "Secrets"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [local.secret_arn]
    }
  }

  dynamic "statement" {
    for_each = var.secret_kms_key_arn != null ? [1] : []
    content {
      sid       = "SecretsKms"
      actions   = ["kms:Decrypt"]
      resources = [var.secret_kms_key_arn]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${local.region}.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.config_in_ssm ? [1] : []
    content {
      sid       = "ConfigSsm"
      actions   = ["ssm:GetParameter"]
      resources = [local.config_ssm_arn]
    }
  }

  dynamic "statement" {
    for_each = local.config_in_s3 ? [1] : []
    content {
      sid       = "ConfigS3"
      actions   = ["s3:GetObject"]
      resources = [local.config_s3_arn]
    }
  }

  dynamic "statement" {
    for_each = local.config_in_s3 && var.config_s3_kms_key_arn != null ? [1] : []
    content {
      sid       = "ConfigKms"
      actions   = ["kms:Decrypt"]
      resources = [var.config_s3_kms_key_arn]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.route53_role_arns) > 0 ? [1] : []
    content {
      sid       = "AssumeRoute53Roles"
      actions   = ["sts:AssumeRole"]
      resources = var.route53_role_arns
    }
  }

  dynamic "statement" {
    for_each = var.identity_store_role_arn != null ? [1] : []
    content {
      sid       = "AssumeIdentityStoreRole"
      actions   = ["sts:AssumeRole"]
      resources = [var.identity_store_role_arn]
    }
  }

  dynamic "statement" {
    for_each = local.lambda_in_vpc ? [1] : []
    content {
      sid = "VpcNetworkInterfaces"
      actions = [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeSubnets",
        "ec2:DeleteNetworkInterface",
        "ec2:AssignPrivateIpAddresses",
        "ec2:UnassignPrivateIpAddresses",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "dns-gate"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_iam_role_policy" "lambda_additional" {
  count = var.lambda_additional_policy_json != null ? 1 : 0

  name   = "additional"
  role   = aws_iam_role.lambda.id
  policy = var.lambda_additional_policy_json
}

# -----------------------------------------------------------------------------
# EventBridge Scheduler role (maintenance task)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  count = var.enable_maintenance_schedule ? 1 : 0

  name                 = "${var.name}-scheduler"
  description          = "Invokes the dns-gate maintenance task (${var.name})"
  assume_role_policy   = data.aws_iam_policy_document.scheduler_assume.json
  permissions_boundary = var.iam_permissions_boundary_arn

  tags = var.tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.enable_maintenance_schedule ? 1 : 0

  name = "invoke-lambda"
  role = aws_iam_role.scheduler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = [aws_lambda_function.this.arn, "${aws_lambda_function.this.arn}:*"]
    }]
  })
}
