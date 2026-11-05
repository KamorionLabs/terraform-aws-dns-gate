# Plan-only tests of modules/identity-center-saml-app with a mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-0123456789abcdef"]
      identity_store_ids = ["d-0123456789"]
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "333333333333"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

run "saml_app" {
  command = plan

  module {
    source = "./modules/identity-center-saml-app"
  }

  variables {
    gate_domain_name           = "dns-gate.example.com"
    assigned_groups            = ["group-1", "group-2"]
    create_identity_store_role = true
    gate_role_arns             = ["arn:aws:iam::111111111111:role/dns-gate-lambda"]
  }

  assert {
    condition     = output.saml_acs_url == "https://dns-gate.example.com/auth/saml/acs"
    error_message = "Unexpected ACS URL"
  }

  assert {
    condition     = output.saml_audience == "https://dns-gate.example.com/auth/saml/metadata"
    error_message = "Unexpected default audience"
  }

  assert {
    condition     = aws_ssoadmin_application.this.portal_options[0].sign_in_options[0].application_url == "https://dns-gate.example.com/"
    error_message = "Unexpected start URL"
  }

  assert {
    condition     = length(aws_ssoadmin_application_assignment.groups) == 2
    error_message = "Groups must be assigned"
  }

  assert {
    condition     = strcontains(output.saml_configuration_instructions, "$${user:email}") && strcontains(output.saml_configuration_instructions, "$${user:name}")
    error_message = "Instructions must list the attribute mappings"
  }

  assert {
    condition     = length(aws_iam_role.identity_store) == 1
    error_message = "Identity store reader role expected"
  }
}

run "identity_store_role_needs_gate_roles" {
  command = plan

  module {
    source = "./modules/identity-center-saml-app"
  }

  variables {
    gate_domain_name           = "dns-gate.example.com"
    create_identity_store_role = true
  }

  expect_failures = [aws_iam_role.identity_store]
}
