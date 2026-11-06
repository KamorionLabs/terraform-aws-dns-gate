# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "gate_domain_name" {
  description = "Public domain of the gate (e.g. 'dns-gate.example.com'): start URL, ACS URL and default audience derive from it."
  type        = string
}

# -----------------------------------------------------------------------------
# Optional Variables
# -----------------------------------------------------------------------------

variable "application_name" {
  description = "Display name to give the Identity Center application in the console."
  type        = string
  default     = "dns-gate"
}

variable "saml_audience" {
  description = "SAML audience (SP entity id) of the gate. Must equal the entity id configured in the gate. Null: https://<gate_domain_name>/auth/saml/metadata."
  type        = string
  default     = null
}

variable "application_arn" {
  description = "ARN of the custom SAML 2.0 application created in the Identity Center console (see saml_configuration_instructions). Null until it exists: no assignment is managed."
  type        = string
  default     = null

  validation {
    condition     = var.application_arn == null || can(regex("^arn:aws:sso::[0-9]{12}:application/ssoins-[0-9a-f]+/apl-[0-9a-f]+$", var.application_arn))
    error_message = "application_arn must be an Identity Center application ARN (arn:aws:sso::<account>:application/ssoins-.../apl-...)."
  }
}

# Assignment by ID
variable "assigned_users" {
  description = "Identity store user ids assigned to the application."
  type        = list(string)
  default     = []
}

variable "assigned_groups" {
  description = "Identity store group ids assigned to the application."
  type        = list(string)
  default     = []
}

# Assignment by name (convenience)
variable "assigned_user_names" {
  description = "User names assigned to the application (looked up in the identity store)."
  type        = list(string)
  default     = []
}

variable "assigned_group_names" {
  description = "Group display names assigned to the application (looked up in the identity store)."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Identity store reader role (optional)
# -----------------------------------------------------------------------------

variable "create_identity_store_role" {
  description = "Create a role the gate assumes to read users and group memberships of the identity store (identity_store_role_arn of the root module). Identity Center SAML assertions carry no group."
  type        = bool
  default     = false
}

variable "identity_store_role_name" {
  description = "Name of the identity store reader role."
  type        = string
  default     = "dns-gate-identity-store-reader"
}

variable "gate_role_arns" {
  description = "Gate function roles allowed to assume the identity store reader role (output lambda_role_arn of the root module)."
  type        = list(string)
  default     = []
}

variable "identity_store_role_external_id" {
  description = "External id required to assume the identity store reader role (optional)."
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary of the identity store reader role (optional)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the application and the role."
  type        = map(string)
  default     = {}
}
