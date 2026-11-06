# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "name" {
  description = "Base name for every resource (e.g. 'dns-gate'). Also the default DynamoDB table name and SSM parameter prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,40}$", var.name))
    error_message = "name must be 1-41 characters: letters, digits and hyphens, starting with a letter or digit."
  }
}

# -----------------------------------------------------------------------------
# Lambda package
# -----------------------------------------------------------------------------

variable "lambda_zip_path" {
  description = "Local path of the release asset dns-gate_<version>_lambda_arm64.zip. Exclusive with lambda_s3_bucket/lambda_s3_key."
  type        = string
  default     = null
}

variable "lambda_s3_bucket" {
  description = "S3 bucket holding the Lambda zip (same region as the function). Exclusive with lambda_zip_path."
  type        = string
  default     = null
}

variable "lambda_s3_key" {
  description = "S3 key of the Lambda zip. Put the version in the key (e.g. 'dns-gate/dns-gate_1.4.0_lambda_arm64.zip') so that an upgrade changes it."
  type        = string
  default     = null
}

variable "lambda_s3_object_version" {
  description = "Object version of the Lambda zip in a versioned bucket (optional)."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Lambda runtime
# -----------------------------------------------------------------------------

variable "lambda_memory_size" {
  description = "Lambda memory in MB (CPU scales with it)."
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds, sized for the maintenance task (reconcile of every zone). HTTP requests are cut at 30 s by API Gateway whatever this value."
  type        = number
  default     = 120

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "lambda_timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_reserved_concurrent_executions" {
  description = "Reserved concurrency of the function. Caps the parallel calls to the DNS provider APIs and the concurrent zone writes. Null: unreserved."
  type        = number
  default     = 5
}

variable "lambda_environment_variables" {
  description = "Extra environment variables of the function. DNS_GATE_CONFIG_URI, DNS_GATE_SECRETS_ARN and DNS_GATE_CONFIG_VERSION are set by the module and cannot be overridden. A variable set here wins over the same key of the secret: never put secrets here, nor the keys of the secret."
  type        = map(string)
  default     = {}
}

variable "lambda_vpc_subnet_ids" {
  description = "Private subnets to run the function in (optional). Needed for a fixed egress IP through a NAT gateway, e.g. when the EuroDNS API key is IP-restricted."
  type        = list(string)
  default     = []
}

variable "lambda_vpc_security_group_ids" {
  description = "Security groups of the function when lambda_vpc_subnet_ids is set (egress HTTPS only is enough)."
  type        = list(string)
  default     = []
}

variable "lambda_additional_policy_json" {
  description = "Extra IAM policy document (JSON) attached to the function role, as an escape hatch for permissions this module does not grant."
  type        = string
  default     = null
}

variable "iam_permissions_boundary_arn" {
  description = "Permissions boundary applied to the IAM roles created by the module (optional)."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Cross-account access
# -----------------------------------------------------------------------------

variable "route53_role_arns" {
  description = "IAM roles the gate assumes to manage Route53 hosted zones in other accounts (see modules/route53-access). Must match providers[].route53.assume_role_arn in the gate configuration."
  type        = list(string)
  default     = []
}

variable "identity_store_role_arn" {
  description = "IAM role the gate assumes to read users and group memberships in the IAM Identity Center identity store (optional, see modules/identity-center-saml-app)."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

variable "config_yaml" {
  description = "dns-gate configuration (YAML). Its store section must point at the DynamoDB table of the module (output dynamodb_table_name). Null when config_uri points at a configuration managed elsewhere."
  type        = string
  default     = null
}

variable "config_storage" {
  description = "Where the module stores config_yaml: 'ssm' (SSM parameter, Advanced tier above 4 KB, max 8 KB) or 's3' (object in config_s3_bucket)."
  type        = string
  default     = "ssm"

  validation {
    condition     = contains(["ssm", "s3"], var.config_storage)
    error_message = "config_storage must be 'ssm' or 's3'."
  }
}

variable "config_ssm_parameter_name" {
  description = "Name of the SSM parameter holding the configuration (default: /<name>/config)."
  type        = string
  default     = null
}

variable "config_s3_bucket" {
  description = "Existing S3 bucket receiving the configuration object when config_storage = 's3'."
  type        = string
  default     = null
}

variable "config_s3_key" {
  description = "S3 key of the configuration object (default: <name>/config.yaml)."
  type        = string
  default     = null
}

variable "config_s3_kms_key_arn" {
  description = "KMS key encrypting the configuration bucket (SSE-KMS), granted kms:Decrypt to the function. Null for SSE-S3."
  type        = string
  default     = null
}

variable "config_uri" {
  description = "Configuration managed outside the module: a file path or file:// URI inside the zip, s3://bucket/key or ssm:/name (SecureString accepted). When set, config_yaml must be null; grant read access (and kms:Decrypt for a CMK) with lambda_additional_policy_json."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------

variable "create_secret" {
  description = "Create the Secrets Manager secret (JSON, keys = environment variable names) with a placeholder value to replace out of Terraform. False to use secret_arn."
  type        = bool
  default     = true
}

variable "secret_arn" {
  description = "Existing Secrets Manager secret (JSON, keys = environment variable names) when create_secret = false."
  type        = string
  default     = null
}

variable "secret_name" {
  description = "Name of the created secret (default: <name>)."
  type        = string
  default     = null
}

variable "secret_placeholder_keys" {
  description = "Keys of the placeholder JSON written once at creation (values 'REPLACE_ME'). Later changes of the value are ignored by Terraform."
  type        = list(string)
  default     = ["DNS_GATE_SESSION_KEY", "DNS_GATE_TOKEN_SIGNING_KEY", "DNS_GATE_SAML_SP_KEY"]
}

variable "secret_kms_key_arn" {
  description = "Customer managed KMS key of the secret (null: aws/secretsmanager). Also used to grant kms:Decrypt for an existing secret."
  type        = string
  default     = null
}

variable "secret_recovery_window_in_days" {
  description = "Recovery window of the created secret when it is deleted (0 deletes immediately)."
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# DynamoDB store
# -----------------------------------------------------------------------------

variable "dynamodb_table_name" {
  description = "Name of the store table (default: <name>). The gate configuration must use the same name in store.dynamodb.table."
  type        = string
  default     = null
}

variable "dynamodb_kms_key_arn" {
  description = "Customer managed KMS key of the table (null: AWS owned key)."
  type        = string
  default     = null
}

variable "dynamodb_point_in_time_recovery" {
  description = "Enable point-in-time recovery (35 days of continuous backups)."
  type        = bool
  default     = true
}

variable "dynamodb_deletion_protection" {
  description = "Enable deletion protection on the table."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# API Gateway HTTP API
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Custom domain of the gate (e.g. 'dns-gate.example.com'). Null keeps the execute-api endpoint only."
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate (same region) for domain_name. Exclusive with create_certificate."
  type        = string
  default     = null
}

variable "create_certificate" {
  description = "Create an ACM certificate for domain_name with DNS validation."
  type        = bool
  default     = false
}

variable "certificate_validation_zone_id" {
  description = "Route53 zone (in the account of the default provider) receiving the ACM validation record. Null when the zone lives in another account: create the record from output certificate_validation_record, the module waits for the certificate."
  type        = string
  default     = null
}

variable "disable_execute_api_endpoint" {
  description = "Disable the default execute-api endpoint (null: disabled when domain_name is set, so that every request reaches the gate under its public name)."
  type        = bool
  default     = null
}

variable "api_throttling_burst_limit" {
  description = "Default route burst limit of the HTTP API stage."
  type        = number
  default     = 100
}

variable "api_throttling_rate_limit" {
  description = "Default route steady-state rate limit (requests per second) of the HTTP API stage."
  type        = number
  default     = 50
}

# -----------------------------------------------------------------------------
# Maintenance schedule
# -----------------------------------------------------------------------------

variable "enable_maintenance_schedule" {
  description = "Create the EventBridge Scheduler schedule invoking the maintenance task (reconcile, discovery, garbage collection)."
  type        = bool
  default     = true
}

variable "maintenance_schedule_expression" {
  description = "Schedule expression of the maintenance task."
  type        = string
  default     = "rate(5 minutes)"
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Retention of the Lambda and API Gateway access log groups."
  type        = number
  default     = 30
}

variable "logs_kms_key_arn" {
  description = "KMS key encrypting the log groups (optional, its key policy must allow CloudWatch Logs)."
  type        = string
  default     = null
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic receiving the alarms (Lambda errors and throttles, API 5xx). Null creates no alarm."
  type        = string
  default     = null
}

variable "alarm_api_5xx_threshold" {
  description = "Number of 5xx responses over 5 minutes raising the API alarm."
  type        = number
  default     = 5
}

variable "audit_export" {
  description = <<-EOT
    Forward the audit events of the function log group to a SIEM or an archive: a subscription filter (default pattern { $.type = "audit" }) towards destination_arn, a Kinesis Data Firehose delivery stream, a Kinesis data stream, a Lambda function or a CloudWatch Logs destination (cross-account). For Firehose and Kinesis the module creates the role CloudWatch Logs assumes unless role_arn is given; for a Lambda function it adds the invoke permission. distribution (ByLogStream or Random) applies to Kinesis data streams only. Null exports nothing.
  EOT
  type = object({
    destination_arn = string
    role_arn        = optional(string)
    filter_name     = optional(string)
    filter_pattern  = optional(string, "{ $.type = \"audit\" }")
    distribution    = optional(string, "ByLogStream")
  })
  default = null

  validation {
    condition     = var.audit_export == null ? true : can(regex("^arn:[^:]+:(firehose|kinesis|lambda|logs):[^:]*:[0-9]{12}:", var.audit_export.destination_arn))
    error_message = "audit_export.destination_arn must be the ARN of a Firehose delivery stream, a Kinesis data stream, a Lambda function or a CloudWatch Logs destination."
  }

  validation {
    condition     = var.audit_export == null ? true : contains(["ByLogStream", "Random"], var.audit_export.distribution)
    error_message = "audit_export.distribution must be ByLogStream or Random."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
