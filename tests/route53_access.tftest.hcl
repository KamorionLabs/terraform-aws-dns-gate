# Plan-only tests of modules/route53-access with a mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_route53_zone" {
    defaults = {
      name = "Example.COM."
    }
  }
}

run "route53_access_policy" {
  command = plan

  module {
    source = "./modules/route53-access"
  }

  variables {
    gate_role_arns      = ["arn:aws:iam::111111111111:role/dns-gate-lambda"]
    hosted_zone_ids     = ["Z0123456789EXAMPLEAAA"]
    external_id         = "dns-gate-example"
    denied_record_names = ["WWW.example.com.", "*.internal.example.com"]
  }

  assert {
    condition     = output.hosted_zones["Z0123456789EXAMPLEAAA"] == "example.com"
    error_message = "Apex must be normalized (lowercase, no trailing dot)"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(output.policy_json).Statement : try(
        s.Effect == "Deny"
        && s.Resource == "arn:aws:route53:::hostedzone/Z0123456789EXAMPLEAAA"
        && s.Condition["ForAnyValue:StringEquals"]["route53:ChangeResourceRecordSetsNormalizedRecordNames"] == ["example.com"]
        && s.Condition["ForAnyValue:StringEquals"]["route53:ChangeResourceRecordSetsRecordTypes"] == ["NS", "SOA"],
        false
      )
    ])
    error_message = "Apex NS/SOA deny statement missing"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(output.policy_json).Statement : try(
        s.Sid == "DenyReservedNames"
        && s.Condition["ForAnyValue:StringLike"]["route53:ChangeResourceRecordSetsNormalizedRecordNames"] == ["www.example.com", "*.internal.example.com"],
        false
      )
    ])
    error_message = "Reserved names deny statement missing or not normalized"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(output.policy_json).Statement : try(
        s.Sid == "ManagedZones" && s.Resource == ["arn:aws:route53:::hostedzone/Z0123456789EXAMPLEAAA"],
        false
      )
    ])
    error_message = "Zone access must be limited to the given zones"
  }
}

run "route53_access_without_denies" {
  command = plan

  module {
    source = "./modules/route53-access"
  }

  variables {
    gate_role_arns      = ["arn:aws:iam::111111111111:role/dns-gate-lambda"]
    hosted_zone_ids     = ["Z0123456789EXAMPLEAAA"]
    protect_apex_ns_soa = false
  }

  assert {
    condition     = alltrue([for s in jsondecode(output.policy_json).Statement : s.Effect == "Allow"])
    error_message = "No deny statement expected"
  }
}
