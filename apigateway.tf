# -----------------------------------------------------------------------------
# API Gateway HTTP API: $default route -> Lambda proxy (payload 2.0)
# -----------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "this" {
  name                         = var.name
  description                  = "dns-gate (${var.name})"
  protocol_type                = "HTTP"
  disable_execute_api_endpoint = local.disable_execute_api

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.this.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.api_throttling_burst_limit
    throttling_rate_limit  = var.api_throttling_rate_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      time               = "$context.requestTime"
      ip                 = "$context.identity.sourceIp"
      userAgent          = "$context.identity.userAgent"
      method             = "$context.httpMethod"
      path               = "$context.path"
      protocol           = "$context.protocol"
      status             = "$context.status"
      responseLength     = "$context.responseLength"
      latencyMs          = "$context.responseLatency"
      integrationStatus  = "$context.integrationStatus"
      integrationLatency = "$context.integration.latency"
      integrationError   = "$context.integrationErrorMessage"
      domainName         = "$context.domainName"
    })
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Custom domain (optional), with an optional ACM certificate
# -----------------------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  count = local.create_domain && var.create_certificate ? 1 : 0

  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = merge(var.tags, { Name = var.domain_name })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  certificate_validation_record = length(aws_acm_certificate.this) > 0 ? {
    name  = one(aws_acm_certificate.this[0].domain_validation_options).resource_record_name
    type  = one(aws_acm_certificate.this[0].domain_validation_options).resource_record_type
    value = one(aws_acm_certificate.this[0].domain_validation_options).resource_record_value
  } : null
}

resource "aws_route53_record" "certificate_validation" {
  count = local.create_domain && var.create_certificate && var.certificate_validation_zone_id != null ? 1 : 0

  zone_id         = var.certificate_validation_zone_id
  name            = local.certificate_validation_record.name
  type            = local.certificate_validation_record.type
  records         = [local.certificate_validation_record.value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count = local.create_domain && var.create_certificate ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = var.certificate_validation_zone_id != null ? [aws_route53_record.certificate_validation[0].fqdn] : null
}

resource "aws_apigatewayv2_domain_name" "this" {
  count = local.create_domain ? 1 : 0

  domain_name = var.domain_name

  domain_name_configuration {
    certificate_arn = local.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.create_certificate != (var.certificate_arn != null)
      error_message = "domain_name requires either certificate_arn or create_certificate = true (not both)."
    }
  }
}

resource "aws_apigatewayv2_api_mapping" "this" {
  count = local.create_domain ? 1 : 0

  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.this[0].id
  stage       = aws_apigatewayv2_stage.default.id
}
