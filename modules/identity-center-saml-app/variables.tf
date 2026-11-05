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
  description = "Display name of the Identity Center application."
  type        = string
  default     = "dns-gate"
}

variable "application_description" {
  description = "Description of the Identity Center application."
  type        = string
  default     = "dns-gate: security gateway in front of DNS provider APIs"
}

variable "saml_audience" {
  description = "SAML audience (SP entity id) of the gate. Must equal the entity id configured in the gate. Null: https://<gate_domain_name>/auth/saml/metadata."
  type        = string
  default     = null
}

variable "portal_visibility" {
  description = "Whether the application tile is shown in the access portal. Valid values: ENABLED, DISABLED."
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.portal_visibility)
    error_message = "portal_visibility must be ENABLED or DISABLED."
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
