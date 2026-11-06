# -----------------------------------------------------------------------------
# Lambda
# -----------------------------------------------------------------------------

output "lambda_function_name" {
  description = "Name of the gate function"
  value       = aws_lambda_function.this.function_name
}

output "lambda_function_arn" {
  description = "ARN of the gate function"
  value       = aws_lambda_function.this.arn
}

output "lambda_role_arn" {
  description = "ARN of the function role: trusted principal of the route53-access and identity store roles"
  value       = aws_iam_role.lambda.arn
}

output "lambda_role_name" {
  description = "Name of the function role"
  value       = aws_iam_role.lambda.name
}

output "lambda_log_group_name" {
  description = "Log group of the function"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "audit_export_role_arn" {
  description = "Role CloudWatch Logs assumes to deliver the audit events (created or given), null without audit_export or for a Lambda or Logs destination"
  value       = local.audit_export ? local.audit_export_role_arn : null
}

# -----------------------------------------------------------------------------
# Store, configuration, secrets
# -----------------------------------------------------------------------------

output "dynamodb_table_name" {
  description = "Store table: store.dynamodb.table in the gate configuration"
  value       = aws_dynamodb_table.this.name
}

output "dynamodb_table_arn" {
  description = "ARN of the store table"
  value       = aws_dynamodb_table.this.arn
}

output "config_uri" {
  description = "DNS_GATE_CONFIG_URI given to the function"
  value       = local.config_uri
}

output "config_ssm_parameter_name" {
  description = "SSM parameter holding the configuration (null unless config_storage = ssm)"
  value       = local.config_in_ssm ? aws_ssm_parameter.config[0].name : null
}

output "config_ssm_parameter_tier" {
  description = "Tier of the configuration parameter (Advanced above 4 KB)"
  value       = local.config_in_ssm ? aws_ssm_parameter.config[0].tier : null
}

output "secret_arn" {
  description = "Secrets Manager secret read at startup (DNS_GATE_SECRETS_ARN)"
  value       = local.secret_arn
}

# -----------------------------------------------------------------------------
# HTTP API and DNS
# -----------------------------------------------------------------------------

output "api_id" {
  description = "ID of the HTTP API"
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Default execute-api endpoint (disabled when a custom domain is set, unless disable_execute_api_endpoint = false)"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "url" {
  description = "Public URL of the gate"
  value       = local.create_domain ? "https://${var.domain_name}" : aws_apigatewayv2_api.this.api_endpoint
}

output "domain_target_domain_name" {
  description = "Target of the gate DNS record (alias A/AAAA, or CNAME)"
  value       = local.create_domain ? aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].target_domain_name : null
}

output "domain_hosted_zone_id" {
  description = "Hosted zone id of the target, for an alias record"
  value       = local.create_domain ? aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].hosted_zone_id : null
}

output "certificate_arn" {
  description = "ACM certificate of the custom domain"
  value       = local.create_domain ? local.certificate_arn : null
}

output "certificate_validation_record" {
  description = "DNS record validating the created certificate ({name, type, value}), to create when the zone is in another account"
  value       = local.certificate_validation_record
}

output "saml_acs_url" {
  description = "SAML Assertion Consumer Service URL to declare in IAM Identity Center"
  value       = local.create_domain ? "https://${var.domain_name}/auth/saml/acs" : null
}

# -----------------------------------------------------------------------------
# Maintenance
# -----------------------------------------------------------------------------

output "maintenance_schedule_arn" {
  description = "ARN of the maintenance schedule"
  value       = var.enable_maintenance_schedule ? aws_scheduler_schedule.maintenance[0].arn : null
}

output "maintenance_invoke_command" {
  description = "AWS CLI command running the maintenance task once"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.this.function_name} --cli-binary-format raw-in-base64-out --payload '${local.maintenance_payload}' /dev/stdout --region ${local.region}"
}
