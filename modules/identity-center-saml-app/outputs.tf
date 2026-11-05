# -----------------------------------------------------------------------------
# Application Outputs
# -----------------------------------------------------------------------------

output "application_arn" {
  description = "ARN of the Identity Center application"
  value       = aws_ssoadmin_application.this.arn
}

output "instance_arn" {
  description = "ARN of the Identity Center instance"
  value       = local.instance_arn
}

output "identity_store_id" {
  description = "ID of the identity store"
  value       = local.identity_store_id
}

output "saml_acs_url" {
  description = "ACS URL to set in the application"
  value       = local.acs_url
}

output "saml_audience" {
  description = "SAML audience (SP entity id) to set in the application and in the gate"
  value       = local.saml_audience
}

output "identity_store_role_arn" {
  description = "Role the gate assumes to read the identity store (identity_store_role_arn of the root module), null when not created"
  value       = var.create_identity_store_role ? aws_iam_role.identity_store[0].arn : null
}

# -----------------------------------------------------------------------------
# SAML Configuration - IMPORTANT
# These values must be configured manually in Identity Center console
# -----------------------------------------------------------------------------

output "saml_configuration_instructions" {
  description = "Console steps completing the SAML configuration (not available through the API)"
  value       = <<-EOT

    ============================================================
    MANUAL CONFIGURATION REQUIRED IN IDENTITY CENTER CONSOLE
    ============================================================

    The Identity Center API cannot set the SAML metadata nor the
    attribute mappings of a custom application. Once applied:

    1. IAM Identity Center > Applications > Customer managed >
       ${var.application_name}
    2. Actions > Edit configuration > Application metadata,
       "Manually type your metadata values":
       - Application ACS URL       : ${local.acs_url}
       - Application SAML audience : ${local.saml_audience}
       (or upload the SP metadata served by the gate, when available)
    3. In the same page, copy "IAM Identity Center SAML metadata file"
       URL (or download the file): the gate configuration needs it
       (IdP metadata URL or XML).
    4. Actions > Edit attribute mappings:
       - Subject : $${user:email}  format emailAddress
       - email   : $${user:email}  format unspecified
       - name    : $${user:name}   format unspecified
       Identity Center does not send groups in the assertion: the gate
       resolves them through the identity store (identity_store_role_arn).
    5. Assignments are managed by Terraform (assigned_* variables);
       users not assigned cannot sign in (assignment required).

    ============================================================
  EOT
}
