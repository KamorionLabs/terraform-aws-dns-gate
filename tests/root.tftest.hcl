# Tests with a mocked AWS provider: no credentials, no AWS call ("apply"
# runs only resolve the mocked computed values).

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

run "defaults" {
  command = apply

  assert {
    condition     = aws_lambda_function.this.runtime == "provided.al2023" && aws_lambda_function.this.architectures[0] == "arm64" && aws_lambda_function.this.handler == "bootstrap"
    error_message = "Function must run the bootstrap binary on provided.al2023 arm64"
  }

  assert {
    condition     = aws_lambda_function.this.memory_size == 512 && aws_lambda_function.this.timeout == 120
    error_message = "Unexpected memory or timeout defaults"
  }

  assert {
    condition     = aws_lambda_function.this.reserved_concurrent_executions == 5
    error_message = "Concurrency must be reserved (5) by default"
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.this.maximum_retry_attempts == 0 && aws_scheduler_schedule.maintenance[0].target[0].retry_policy[0].maximum_retry_attempts == 0
    error_message = "Maintenance invocations must never be retried"
  }

  assert {
    condition     = aws_ssm_parameter.config[0].tier == "Standard" && aws_ssm_parameter.config[0].type == "String"
    error_message = "A small configuration must use a Standard String parameter"
  }

  assert {
    condition     = output.config_uri == "ssm:/dns-gate/config"
    error_message = "Unexpected config URI: ${output.config_uri}"
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables["DNS_GATE_CONFIG_URI"] == "ssm:/dns-gate/config"
    error_message = "DNS_GATE_CONFIG_URI not set"
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables["DNS_GATE_SECRETS_ARN"] == "arn:aws:secretsmanager:eu-west-3:111111111111:secret:dns-gate-AbCdEf"
    error_message = "DNS_GATE_SECRETS_ARN not set"
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables["DNS_GATE_CONFIG_VERSION"] == sha256(var.config_yaml)
    error_message = "DNS_GATE_CONFIG_VERSION must follow the configuration"
  }

  assert {
    condition     = aws_dynamodb_table.this.name == "dns-gate" && aws_dynamodb_table.this.hash_key == "pk" && aws_dynamodb_table.this.range_key == "sk"
    error_message = "Table must use the store key schema pk/sk"
  }

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PAY_PER_REQUEST" && aws_dynamodb_table.this.deletion_protection_enabled
    error_message = "Table must be on-demand and protected"
  }

  assert {
    condition     = aws_dynamodb_table.this.ttl[0].attribute_name == "ttl" && aws_dynamodb_table.this.ttl[0].enabled
    error_message = "TTL must be enabled on the ttl attribute"
  }

  assert {
    condition     = aws_dynamodb_table.this.point_in_time_recovery[0].enabled
    error_message = "PITR must be enabled"
  }

  assert {
    condition     = jsondecode(aws_secretsmanager_secret_version.placeholder[0].secret_string)["DNS_GATE_SESSION_KEY"] == "REPLACE_ME"
    error_message = "Placeholder secret must list the expected keys"
  }

  assert {
    condition     = aws_apigatewayv2_integration.lambda.payload_format_version == "2.0" && aws_apigatewayv2_route.default.route_key == "$default"
    error_message = "HTTP API must proxy $default with payload 2.0"
  }

  assert {
    condition     = !aws_apigatewayv2_api.this.disable_execute_api_endpoint && length(aws_apigatewayv2_domain_name.this) == 0
    error_message = "Without a domain the execute-api endpoint stays enabled"
  }

  assert {
    condition     = aws_scheduler_schedule.maintenance[0].schedule_expression == "rate(5 minutes)" && jsondecode(aws_scheduler_schedule.maintenance[0].target[0].input).dns_gate_task == "maintenance"
    error_message = "Maintenance schedule must send the maintenance task every 5 minutes"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.lambda_errors) == 0
    error_message = "No alarm without an SNS topic"
  }
}

run "large_config_uses_advanced_tier" {
  command = plan

  variables {
    config_yaml = join("\n", [for i in range(300) : "# padding line ${i}"])
  }

  assert {
    condition     = aws_ssm_parameter.config[0].tier == "Advanced"
    error_message = "A configuration above 4 KB needs the Advanced tier"
  }
}

run "config_too_large_for_ssm" {
  command = plan

  variables {
    config_yaml = join("\n", [for i in range(600) : "# padding line number ${i}"])
  }

  expect_failures = [aws_ssm_parameter.config]
}

run "config_in_s3" {
  command = plan

  variables {
    config_storage   = "s3"
    config_s3_bucket = "config-bucket"
  }

  assert {
    condition     = output.config_uri == "s3://config-bucket/dns-gate/config.yaml" && length(aws_ssm_parameter.config) == 0
    error_message = "S3 storage must write the object and point the URI at it"
  }

  assert {
    condition     = aws_s3_object.config[0].key == "dns-gate/config.yaml"
    error_message = "Unexpected configuration key"
  }
}

run "external_secret_and_config" {
  command = plan

  variables {
    config_yaml   = null
    config_uri    = "ssm:/elsewhere/config"
    create_secret = false
    secret_arn    = "arn:aws:secretsmanager:eu-west-3:111111111111:secret:existing-XyZ123"
  }

  assert {
    condition     = length(aws_secretsmanager_secret.this) == 0 && length(aws_ssm_parameter.config) == 0 && length(aws_s3_object.config) == 0
    error_message = "Nothing must be created for an external secret and configuration"
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables["DNS_GATE_SECRETS_ARN"] == var.secret_arn
    error_message = "The existing secret must be passed to the function"
  }
}

run "zip_and_s3_are_exclusive" {
  command = plan

  variables {
    lambda_zip_path = "dns-gate.zip"
  }

  expect_failures = [aws_lambda_function.this]
}

run "custom_domain_with_certificate" {
  command = apply

  variables {
    domain_name                    = "dns-gate.example.com"
    create_certificate             = true
    certificate_validation_zone_id = "Z0123456789EXAMPLEAAA"
    alarm_sns_topic_arn            = "arn:aws:sns:eu-west-3:111111111111:alerts"
  }

  assert {
    condition     = aws_apigatewayv2_api.this.disable_execute_api_endpoint
    error_message = "With a custom domain the execute-api endpoint is disabled"
  }

  assert {
    condition     = aws_route53_record.certificate_validation[0].name == "_abc.dns-gate.example.com." && aws_route53_record.certificate_validation[0].type == "CNAME"
    error_message = "Validation record must come from the certificate"
  }

  assert {
    condition     = output.saml_acs_url == "https://dns-gate.example.com/auth/saml/acs" && output.url == "https://dns-gate.example.com"
    error_message = "Unexpected public URLs"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.lambda_errors) == 1 && length(aws_cloudwatch_metric_alarm.lambda_throttles) == 1 && length(aws_cloudwatch_metric_alarm.api_5xx) == 1
    error_message = "Alarms must exist with an SNS topic"
  }
}

run "custom_domain_without_certificate" {
  command = plan

  variables {
    domain_name = "dns-gate.example.com"
  }

  expect_failures = [aws_apigatewayv2_domain_name.this]
}
