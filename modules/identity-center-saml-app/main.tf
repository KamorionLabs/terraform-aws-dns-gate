# -----------------------------------------------------------------------------
# Identity Center custom SAML application for dns-gate
# Deploy in the account managing IAM Identity Center (management account or
# delegated administrator). The SAML settings (ACS URL, audience, attribute
# mappings) cannot be set through the API: see output
# saml_configuration_instructions.
# -----------------------------------------------------------------------------

data "aws_ssoadmin_instances" "this" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  start_url     = "https://${var.gate_domain_name}/"
  acs_url       = "https://${var.gate_domain_name}/auth/saml/acs"
  saml_audience = coalesce(var.saml_audience, "https://${var.gate_domain_name}/auth/saml/metadata")
}

# -----------------------------------------------------------------------------
# SAML Application
# -----------------------------------------------------------------------------

resource "aws_ssoadmin_application" "this" {
  name                     = var.application_name
  description              = var.application_description
  application_provider_arn = "arn:aws:sso::aws:applicationProvider/custom"
  instance_arn             = local.instance_arn

  portal_options {
    visibility = var.portal_visibility
    sign_in_options {
      origin          = "APPLICATION"
      application_url = local.start_url
    }
  }

  tags = var.tags
}

resource "aws_ssoadmin_application_assignment_configuration" "this" {
  application_arn     = aws_ssoadmin_application.this.arn
  assignment_required = true
}

# -----------------------------------------------------------------------------
# Application Assignment (Users/Groups)
# -----------------------------------------------------------------------------

resource "aws_ssoadmin_application_assignment" "users" {
  for_each = toset(var.assigned_users)

  application_arn = aws_ssoadmin_application.this.arn
  principal_id    = each.value
  principal_type  = "USER"
}

resource "aws_ssoadmin_application_assignment" "groups" {
  for_each = toset(var.assigned_groups)

  application_arn = aws_ssoadmin_application.this.arn
  principal_id    = each.value
  principal_type  = "GROUP"
}

data "aws_identitystore_user" "by_name" {
  for_each = toset(var.assigned_user_names)

  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = each.value
    }
  }
}

data "aws_identitystore_group" "by_name" {
  for_each = toset(var.assigned_group_names)

  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.value
    }
  }
}

resource "aws_ssoadmin_application_assignment" "users_by_name" {
  for_each = data.aws_identitystore_user.by_name

  application_arn = aws_ssoadmin_application.this.arn
  principal_id    = each.value.user_id
  principal_type  = "USER"
}

resource "aws_ssoadmin_application_assignment" "groups_by_name" {
  for_each = data.aws_identitystore_group.by_name

  application_arn = aws_ssoadmin_application.this.arn
  principal_id    = each.value.group_id
  principal_type  = "GROUP"
}

# -----------------------------------------------------------------------------
# Identity store reader role (optional): group resolution by the gate
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "identity_store_assume" {
  count = var.create_identity_store_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.gate_role_arns
    }

    dynamic "condition" {
      for_each = var.identity_store_role_external_id != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = [var.identity_store_role_external_id]
      }
    }
  }
}

resource "aws_iam_role" "identity_store" {
  count = var.create_identity_store_role ? 1 : 0

  name                 = var.identity_store_role_name
  description          = "dns-gate read access to the Identity Center identity store"
  assume_role_policy   = data.aws_iam_policy_document.identity_store_assume[0].json
  permissions_boundary = var.permissions_boundary_arn

  tags = var.tags

  lifecycle {
    precondition {
      condition     = length(var.gate_role_arns) > 0
      error_message = "create_identity_store_role requires gate_role_arns."
    }
  }
}

data "aws_iam_policy_document" "identity_store" {
  count = var.create_identity_store_role ? 1 : 0

  statement {
    sid = "ReadIdentityStore"
    actions = [
      "identitystore:DescribeUser",
      "identitystore:GetUserId",
      "identitystore:ListUsers",
      "identitystore:DescribeGroup",
      "identitystore:GetGroupId",
      "identitystore:ListGroups",
      "identitystore:GetGroupMembershipId",
      "identitystore:DescribeGroupMembership",
      "identitystore:ListGroupMemberships",
      "identitystore:ListGroupMembershipsForMember",
      "identitystore:IsMemberInGroups",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:identitystore::${data.aws_caller_identity.current.account_id}:identitystore/${local.identity_store_id}",
      "arn:${data.aws_partition.current.partition}:identitystore:::user/*",
      "arn:${data.aws_partition.current.partition}:identitystore:::group/*",
      "arn:${data.aws_partition.current.partition}:identitystore:::membership/*",
    ]
  }
}

resource "aws_iam_role_policy" "identity_store" {
  count = var.create_identity_store_role ? 1 : 0

  name   = "identity-store-read"
  role   = aws_iam_role.identity_store[0].id
  policy = data.aws_iam_policy_document.identity_store[0].json
}
