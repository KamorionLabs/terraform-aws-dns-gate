output "role_arn" {
  description = "ARN of the role: providers[].route53.assume_role_arn in the gate configuration, and route53_role_arns of the root module"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the role"
  value       = aws_iam_role.this.name
}

output "external_id" {
  description = "External id required by the role (null: none)"
  value       = var.external_id
}

output "hosted_zones" {
  description = "Managed zones: id => apex name"
  value       = local.zone_apex
}

output "gate_provider_config" {
  description = "route53 block of a gate provider entry (providers[].route53), to render into the gate configuration"
  value = {
    assume_role_arn = aws_iam_role.this.arn
    external_id     = var.external_id
    hosted_zones    = var.hosted_zone_ids
  }
}

output "policy_json" {
  description = "Inline policy of the role (for review)"
  value       = jsonencode(local.route53_policy)
}
