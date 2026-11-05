# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "gate_role_arns" {
  description = "IAM roles allowed to assume this role: the gate function role (output lambda_role_arn of the root module)."
  type        = list(string)

  validation {
    condition     = length(var.gate_role_arns) > 0
    error_message = "gate_role_arns needs at least one role ARN."
  }
}

variable "hosted_zone_ids" {
  description = "Route53 hosted zones (ids, without the /hostedzone/ prefix) the gate may read and change."
  type        = list(string)

  validation {
    condition     = length(var.hosted_zone_ids) > 0 && alltrue([for id in var.hosted_zone_ids : can(regex("^Z[A-Z0-9]+$", id))])
    error_message = "hosted_zone_ids must be a non-empty list of zone ids such as Z0123456789ABCDEFGHIJ."
  }
}

# -----------------------------------------------------------------------------
# Optional Variables
# -----------------------------------------------------------------------------

variable "role_name" {
  description = "Name of the role assumed by the gate."
  type        = string
  default     = "dns-gate-route53"
}

variable "external_id" {
  description = "External id required in the AssumeRole call (providers[].route53.external_id in the gate configuration). Null: no external id."
  type        = string
  default     = null
}

variable "denied_record_names" {
  description = "Record names the gate may never change, in any of the zones (names reserved for other tools, e.g. records managed by Terraform). Lowercase, without trailing dot; '*' and '?' are wildcards (IAM StringLike), e.g. 'www.example.com' or '*.internal.example.com'."
  type        = list(string)
  default     = []
}

variable "protect_apex_ns_soa" {
  description = "Deny changes touching the NS and SOA records of each zone apex."
  type        = bool
  default     = true
}

variable "max_session_duration" {
  description = "Maximum session duration of the role, in seconds."
  type        = number
  default     = 3600
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary of the role (optional)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the role."
  type        = map(string)
  default     = {}
}
