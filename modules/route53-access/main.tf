# -----------------------------------------------------------------------------
# Route53 access for dns-gate
# Deploy in the account owning the hosted zones. The gate function role
# assumes this role (providers[].route53.assume_role_arn in the gate config).
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}

data "aws_route53_zone" "this" {
  for_each = toset(var.hosted_zone_ids)

  zone_id = each.value
}

locals {
  partition = data.aws_partition.current.partition

  zone_arns = { for id in var.hosted_zone_ids : id => "arn:${local.partition}:route53:::hostedzone/${id}" }

  # Route53 compares normalized names: lowercase, no trailing dot.
  zone_apex = { for id, z in data.aws_route53_zone.this : id => lower(trimsuffix(z.name, ".")) }

  denied_record_names = distinct([for n in var.denied_record_names : lower(trimsuffix(n, "."))])
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.gate_role_arns
    }

    dynamic "condition" {
      for_each = var.external_id != null ? [1] : []
      content {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = [var.external_id]
      }
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "dns-gate access to Route53 hosted zones"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn

  tags = var.tags
}

locals {
  allow_statements = [
    {
      Sid      = "ListZones"
      Effect   = "Allow"
      Action   = ["route53:ListHostedZones", "route53:ListHostedZonesByName"]
      Resource = "*"
    },
    {
      Sid      = "GetChange"
      Effect   = "Allow"
      Action   = "route53:GetChange"
      Resource = "arn:${local.partition}:route53:::change/*"
    },
    {
      Sid    = "ManagedZones"
      Effect = "Allow"
      Action = [
        "route53:GetHostedZone",
        "route53:ListResourceRecordSets",
        "route53:ChangeResourceRecordSets",
      ]
      Resource = values(local.zone_arns)
    },
  ]

  # One statement per zone: a change batch naming the apex AND an NS or SOA
  # type is refused. Both conditions are ForAnyValue on the whole batch, so a
  # batch mixing an apex record with a delegation NS elsewhere in the zone is
  # refused too: send such changes in separate batches.
  apex_statements = [
    for id, apex in(var.protect_apex_ns_soa ? local.zone_apex : {}) : {
      Sid      = "DenyApexNsSoa${id}"
      Effect   = "Deny"
      Action   = "route53:ChangeResourceRecordSets"
      Resource = local.zone_arns[id]
      Condition = {
        "ForAnyValue:StringEquals" = {
          "route53:ChangeResourceRecordSetsNormalizedRecordNames" = [apex]
          "route53:ChangeResourceRecordSetsRecordTypes"           = ["NS", "SOA"]
        }
      }
    }
  ]

  reserved_statements = length(local.denied_record_names) == 0 ? [] : [
    {
      Sid      = "DenyReservedNames"
      Effect   = "Deny"
      Action   = "route53:ChangeResourceRecordSets"
      Resource = values(local.zone_arns)
      Condition = {
        "ForAnyValue:StringLike" = {
          "route53:ChangeResourceRecordSetsNormalizedRecordNames" = local.denied_record_names
        }
      }
    }
  ]

  route53_policy = {
    Version   = "2012-10-17"
    Statement = concat(local.allow_statements, local.apex_statements, local.reserved_statements)
  }
}

resource "aws_iam_role_policy" "route53" {
  name   = "route53"
  role   = aws_iam_role.this.id
  policy = jsonencode(local.route53_policy)
}
