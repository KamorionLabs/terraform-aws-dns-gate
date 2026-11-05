data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition

  table_name = coalesce(var.dynamodb_table_name, var.name)

  manage_config   = var.config_uri == null
  config_in_ssm   = local.manage_config && var.config_storage == "ssm"
  config_in_s3    = local.manage_config && var.config_storage == "s3"
  config_bytes    = local.manage_config ? length(coalesce(var.config_yaml, " ")) : 0
  config_ssm_name = coalesce(var.config_ssm_parameter_name, "/${var.name}/config")
  config_s3_key   = coalesce(var.config_s3_key, "${var.name}/config.yaml")
  config_ssm_tier = local.config_bytes > 4096 ? "Advanced" : "Standard"
  config_ssm_arn  = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/${trimprefix(local.config_ssm_name, "/")}"
  config_s3_arn   = local.config_in_s3 ? "arn:${local.partition}:s3:::${var.config_s3_bucket}/${local.config_s3_key}" : null
  config_uri      = local.config_in_ssm ? "ssm:${local.config_ssm_name}" : local.config_in_s3 ? "s3://${var.config_s3_bucket}/${local.config_s3_key}" : var.config_uri
  config_version  = local.manage_config ? sha256(var.config_yaml == null ? "" : var.config_yaml) : sha256(var.config_uri)

  has_secret = var.create_secret || var.secret_arn != null
  secret_arn = var.create_secret ? aws_secretsmanager_secret.this[0].arn : var.secret_arn

  create_domain       = var.domain_name != null
  certificate_arn     = local.create_domain && var.create_certificate ? aws_acm_certificate_validation.this[0].certificate_arn : var.certificate_arn
  disable_execute_api = coalesce(var.disable_execute_api_endpoint, local.create_domain)

  lambda_in_vpc = length(var.lambda_vpc_subnet_ids) > 0

  lambda_environment = merge(
    var.lambda_environment_variables,
    {
      DNS_GATE_CONFIG_URI     = local.config_uri
      DNS_GATE_CONFIG_VERSION = local.config_version
    },
    local.has_secret ? { DNS_GATE_SECRETS_ARN = local.secret_arn } : {},
  )

  maintenance_payload = jsonencode({ dns_gate_task = "maintenance" })

  create_alarms = var.alarm_sns_topic_arn != null
}
