# -----------------------------------------------------------------------------
# Secrets (DNS_GATE_SECRETS_ARN)
# JSON object whose keys are environment variable names. Terraform writes a
# placeholder once and never reads the real values back into the state.
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "this" {
  count = var.create_secret ? 1 : 0

  name                    = coalesce(var.secret_name, var.name)
  description             = "dns-gate secrets (${var.name}): JSON, keys = environment variable names"
  kms_key_id              = var.secret_kms_key_arn
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "placeholder" {
  count = var.create_secret ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this[0].id
  secret_string = jsonencode({ for k in var.secret_placeholder_keys : k => "REPLACE_ME" })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
