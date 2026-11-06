# audit_export: subscription filter of the audit events, with a mocked AWS
# provider.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-3"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/dns-gate-lambda"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-3:111111111111:log-group:dns-gate"
    }
  }

  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:eu-west-3:111111111111:table/dns-gate"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn        = "arn:aws:lambda:eu-west-3:111111111111:function:dns-gate"
      invoke_arn = "arn:aws:apigateway:eu-west-3:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-3:111111111111:function:dns-gate/invocations"
    }
  }

  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      execution_arn = "arn:aws:execute-api:eu-west-3:111111111111:abcdef1234"
      api_endpoint  = "https://abcdef1234.execute-api.eu-west-3.amazonaws.com"
    }
  }

  mock_resource "aws_acm_certificate_validation" {
    defaults = {
      certificate_arn = "arn:aws:acm:eu-west-3:111111111111:certificate/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:eu-west-3:111111111111:secret:dns-gate-AbCdEf"
    }
  }

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:eu-west-3:111111111111:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [{
        domain_name           = "dns-gate.example.com"
        resource_record_name  = "_abc.dns-gate.example.com."
        resource_record_type  = "CNAME"
        resource_record_value = "_def.acm-validations.aws."
      }]
    }
  }
}

variables {
  name             = "dns-gate"
  lambda_s3_bucket = "artifacts"
  lambda_s3_key    = "dns-gate/dns-gate_1.0.0_lambda_arm64.zip"
  config_yaml      = "store:\n  type: dynamodb\n  dynamodb:\n    table: dns-gate\n"
}

run "no_export_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_subscription_filter.audit_export) == 0 && length(aws_iam_role.audit_export) == 0 && length(aws_lambda_permission.audit_export) == 0
    error_message = "Nothing must be exported without audit_export"
  }

  assert {
    condition     = output.audit_export_role_arn == null
    error_message = "No export role without audit_export"
  }
}

run "firehose" {
  command = apply

  variables {
    audit_export = {
      destination_arn = "arn:aws:firehose:eu-west-3:111111111111:deliverystream/dns-gate-audit"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.audit_export[0].filter_pattern == "{ $.type = \"audit\" }" && aws_cloudwatch_log_subscription_filter.audit_export[0].log_group_name == "/aws/lambda/dns-gate"
    error_message = "The filter must select the audit lines of the function log group"
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.audit_export[0].name == "dns-gate-audit" && aws_cloudwatch_log_subscription_filter.audit_export[0].distribution == null
    error_message = "Unexpected filter name or distribution"
  }

  assert {
    condition     = aws_iam_role.audit_export[0].name == "dns-gate-audit-export" && aws_cloudwatch_log_subscription_filter.audit_export[0].role_arn == aws_iam_role.audit_export[0].arn
    error_message = "The filter must use the role created for the delivery"
  }

  assert {
    condition     = output.audit_export_role_arn == aws_iam_role.audit_export[0].arn
    error_message = "The created role must be an output"
  }

  assert {
    condition     = length(aws_lambda_permission.audit_export) == 0
    error_message = "No invoke permission for Firehose"
  }
}

run "firehose_policy" {
  command = plan

  variables {
    audit_export = {
      destination_arn = "arn:aws:firehose:eu-west-3:111111111111:deliverystream/dns-gate-audit"
    }
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.audit_export[0].statement[0].actions) == toset(["firehose:PutRecord", "firehose:PutRecordBatch"]) && data.aws_iam_policy_document.audit_export[0].statement[0].resources == toset(["arn:aws:firehose:eu-west-3:111111111111:deliverystream/dns-gate-audit"])
    error_message = "The role may only put records into the delivery stream"
  }

  assert {
    condition     = alltrue([for p in data.aws_iam_policy_document.audit_export_assume[0].statement[0].principals : p.type == "Service" && contains(p.identifiers, "logs.amazonaws.com") && length(p.identifiers) == 1])
    error_message = "CloudWatch Logs must assume the role"
  }

  assert {
    condition     = anytrue([for c in data.aws_iam_policy_document.audit_export_assume[0].statement[0].condition : c.test == "StringLike" && c.variable == "aws:SourceArn" && contains(c.values, "arn:aws:logs:eu-west-3:111111111111:*")])
    error_message = "The trust must be limited to CloudWatch Logs of this account and region"
  }
}

run "kinesis_with_existing_role" {
  command = plan

  variables {
    audit_export = {
      destination_arn = "arn:aws:kinesis:eu-west-3:111111111111:stream/audit"
      role_arn        = "arn:aws:iam::111111111111:role/existing"
      distribution    = "Random"
      filter_name     = "siem"
    }
  }

  assert {
    condition     = length(aws_iam_role.audit_export) == 0 && aws_cloudwatch_log_subscription_filter.audit_export[0].role_arn == "arn:aws:iam::111111111111:role/existing"
    error_message = "A given role must be used as is"
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.audit_export[0].distribution == "Random" && aws_cloudwatch_log_subscription_filter.audit_export[0].name == "siem"
    error_message = "Distribution and name must be passed for a Kinesis stream"
  }
}

run "kinesis_policy" {
  command = plan

  variables {
    audit_export = {
      destination_arn = "arn:aws:kinesis:eu-west-3:111111111111:stream/audit"
    }
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.audit_export[0].statement[0].actions) == toset(["kinesis:PutRecord", "kinesis:PutRecords"])
    error_message = "The role may only put records into the stream"
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.audit_export[0].distribution == "ByLogStream"
    error_message = "Kinesis streams default to ByLogStream"
  }
}

run "lambda_destination" {
  command = apply

  variables {
    audit_export = {
      destination_arn = "arn:aws:lambda:eu-west-3:111111111111:function:siem-forwarder"
      filter_pattern  = "{ $.type = \"audit\" && $.decision != \"allow\" }"
    }
  }

  assert {
    condition     = length(aws_iam_role.audit_export) == 0 && output.audit_export_role_arn == null
    error_message = "No role for a Lambda destination"
  }

  assert {
    condition     = aws_lambda_permission.audit_export[0].principal == "logs.amazonaws.com" && aws_lambda_permission.audit_export[0].function_name == "arn:aws:lambda:eu-west-3:111111111111:function:siem-forwarder" && aws_lambda_permission.audit_export[0].source_arn == "arn:aws:logs:eu-west-3:111111111111:log-group:dns-gate:*"
    error_message = "CloudWatch Logs must be allowed to invoke the function for this log group only"
  }

  assert {
    condition     = aws_cloudwatch_log_subscription_filter.audit_export[0].filter_pattern == "{ $.type = \"audit\" && $.decision != \"allow\" }"
    error_message = "A custom pattern must be kept"
  }
}

run "logs_destination" {
  command = plan

  variables {
    audit_export = {
      destination_arn = "arn:aws:logs:eu-west-3:222222222222:destination:central-audit"
    }
  }

  assert {
    condition     = length(aws_iam_role.audit_export) == 0 && length(aws_lambda_permission.audit_export) == 0 && output.audit_export_role_arn == null
    error_message = "A CloudWatch Logs destination needs neither role nor permission"
  }
}

run "invalid_destination" {
  command = plan

  variables {
    audit_export = {
      destination_arn = "arn:aws:sqs:eu-west-3:111111111111:queue"
    }
  }

  expect_failures = [var.audit_export]
}

run "invalid_distribution" {
  command = plan

  variables {
    audit_export = {
      destination_arn = "arn:aws:kinesis:eu-west-3:111111111111:stream/audit"
      distribution    = "RoundRobin"
    }
  }

  expect_failures = [var.audit_export]
}
