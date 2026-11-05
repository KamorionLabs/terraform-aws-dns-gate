# -----------------------------------------------------------------------------
# Gate configuration (DNS_GATE_CONFIG_URI)
# The YAML holds no secret: it goes to a String parameter or an S3 object.
# -----------------------------------------------------------------------------

resource "aws_ssm_parameter" "config" {
  count = local.config_in_ssm ? 1 : 0

  name        = local.config_ssm_name
  description = "dns-gate configuration (${var.name})"
  type        = "String"
  tier        = local.config_ssm_tier
  value       = var.config_yaml

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.config_yaml != null
      error_message = "config_yaml is required unless config_uri is set."
    }
    precondition {
      condition     = local.config_bytes <= 8192
      error_message = "config_yaml exceeds 8 KB, the SSM Advanced tier limit: use config_storage = \"s3\"."
    }
  }
}

resource "aws_s3_object" "config" {
  count = local.config_in_s3 ? 1 : 0

  bucket                 = var.config_s3_bucket
  key                    = local.config_s3_key
  content                = var.config_yaml
  content_type           = "application/yaml"
  server_side_encryption = var.config_s3_kms_key_arn != null ? "aws:kms" : null
  kms_key_id             = var.config_s3_kms_key_arn

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.config_yaml != null && var.config_s3_bucket != null
      error_message = "config_storage = \"s3\" requires config_yaml and config_s3_bucket."
    }
  }
}
