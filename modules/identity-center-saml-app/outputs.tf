# -----------------------------------------------------------------------------
# Application Outputs
# -----------------------------------------------------------------------------

output "application_arn" {
  description = "ARN of the Identity Center application (application_arn)"
  value       = var.application_arn
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

    The Identity Center API cannot create a custom SAML 2.0
    application nor set its metadata and attribute mappings.

    1. IAM Identity Center > Applications > Add application >
       "I have an application I want to set up" > SAML 2.0.
       - Display name          : ${var.application_name}
       - Application start URL : ${local.start_url}
    2. Application metadata, "Manually type your metadata values":
       - Application ACS URL       : ${local.acs_url}
       - Application SAML audience : ${local.saml_audience}
    3. Copy the "IAM Identity Center SAML metadata file" URL: the gate
       configuration needs it (IdP metadata URL).
    4. Submit, then Actions > Edit attribute mappings:
       - Subject : $${user:email}  format emailAddress
       - email   : $${user:email}  format unspecified
       - name    : $${user:name}   format unspecified
       Identity Center does not send groups in the assertion: the gate
       resolves them through the identity store (identity_store_role_arn).
    5. Set application_arn to the ARN of the application and apply:
       Terraform assigns the users and groups (assigned_* variables);
       users not assigned cannot sign in.

    ============================================================
  EOT
}
