locals {
  name        = "dns-gate"
  domain_name = "dns-gate.example-corp.net"
  external_id = "dns-gate-example-corp"

  # Zones the gate manages, in the network account
  hosted_zones = {
    "example.com" = "Z0123456789EXAMPLEAAA"
    "example.org" = "Z0123456789EXAMPLEBBB"
  }
  hosted_zone_ids = values(local.hosted_zones)

  # Zone holding the gate record (and the certificate validation record)
  gate_zone_id = "Z0123456789EXAMPLEAAA"

  tags = {
    Project   = "dns-gate"
    ManagedBy = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Network account: role the gate assumes to manage the hosted zones
# -----------------------------------------------------------------------------

module "route53_access" {
  source = "../../modules/route53-access"

  providers = {
    aws = aws.network
  }

  role_name       = "dns-gate-route53"
  gate_role_arns  = [module.dns_gate.lambda_role_arn]
  external_id     = local.external_id
  hosted_zone_ids = local.hosted_zone_ids

  # Records managed by another tool (Terraform stack, ingress controller...)
  denied_record_names = [
    "example-corp.net",
    "www.example-corp.net",
    "dns-gate.example-corp.net",
  ]

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Shared services account: the gate
# -----------------------------------------------------------------------------

module "dns_gate" {
  source = "../../"

  providers = {
    aws = aws.shared
  }

  name = local.name

  # Release asset downloaded next to this file (see README, Upgrade)
  lambda_zip_path = "${path.module}/dns-gate_1.0.0_lambda_arm64.zip"

  config_yaml = templatefile("${path.module}/config.yaml.tftpl", {
    table           = local.name
    region          = "eu-west-3"
    domain_name     = local.domain_name
    assume_role_arn = module.route53_access.role_arn
    external_id     = local.external_id
    hosted_zones    = local.hosted_zones
  })

  route53_role_arns = [module.route53_access.role_arn]

  domain_name        = local.domain_name
  create_certificate = true
  # The zone is in the network account: the validation record is created below

  alarm_sns_topic_arn = "arn:aws:sns:eu-west-3:111111111111:ops-alerts"

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Network account: certificate validation and gate record
# -----------------------------------------------------------------------------

resource "aws_route53_record" "certificate_validation" {
  provider = aws.network

  zone_id         = local.gate_zone_id
  name            = module.dns_gate.certificate_validation_record.name
  type            = module.dns_gate.certificate_validation_record.type
  records         = [module.dns_gate.certificate_validation_record.value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_route53_record" "gate" {
  for_each = toset(["A", "AAAA"])
  provider = aws.network

  zone_id = local.gate_zone_id
  name    = local.domain_name
  type    = each.value

  alias {
    name                   = module.dns_gate.domain_target_domain_name
    zone_id                = module.dns_gate.domain_hosted_zone_id
    evaluate_target_health = false
  }
}

output "url" {
  value = module.dns_gate.url
}

output "saml_acs_url" {
  value = module.dns_gate.saml_acs_url
}

output "secret_arn" {
  value = module.dns_gate.secret_arn
}
