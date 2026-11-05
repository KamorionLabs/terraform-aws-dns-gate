# -----------------------------------------------------------------------------
# Maintenance task: reconcile, zone discovery, garbage collection
# EventBridge Scheduler invokes the function with {"dns_gate_task":"maintenance"}
# -----------------------------------------------------------------------------

resource "aws_scheduler_schedule" "maintenance" {
  count = var.enable_maintenance_schedule ? 1 : 0

  name        = "${var.name}-maintenance"
  description = "dns-gate maintenance task (${var.name})"
  group_name  = "default"

  schedule_expression = var.maintenance_schedule_expression
  state               = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.this.arn
    role_arn = aws_iam_role.scheduler[0].arn
    input    = local.maintenance_payload

    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 300
    }
  }
}
