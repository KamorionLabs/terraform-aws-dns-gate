# identity-center-saml-app

Assignments of the IAM Identity Center custom SAML 2.0 application of the dns-gate login, and an optional read-only identity store role for the gate. Deploy in the account managing Identity Center (management or delegated administrator). The application itself is created in the console (the API cannot create a custom SAML 2.0 application): follow output saml_configuration_instructions, then set application_arn. See the root README.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5 |
| aws | >= 6.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 6.0 |

## Resources

| Name | Type |
|------|------|
| [aws_iam_role.identity_store](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.identity_store](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_ssoadmin_application_assignment.groups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_application_assignment) | resource |
| [aws_ssoadmin_application_assignment.groups_by_name](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_application_assignment) | resource |
| [aws_ssoadmin_application_assignment.users](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_application_assignment) | resource |
| [aws_ssoadmin_application_assignment.users_by_name](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_application_assignment) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.identity_store](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.identity_store_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_identitystore_group.by_name](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/identitystore_group) | data source |
| [aws_identitystore_user.by_name](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/identitystore_user) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_ssoadmin_instances.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssoadmin_instances) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| gate\_domain\_name | Public domain of the gate (e.g. 'dns-gate.example.com'): start URL, ACS URL and default audience derive from it. | `string` | n/a | yes |
| application\_arn | ARN of the custom SAML 2.0 application created in the Identity Center console (see saml\_configuration\_instructions). Null until it exists: no assignment is managed. | `string` | `null` | no |
| application\_name | Display name to give the Identity Center application in the console. | `string` | `"dns-gate"` | no |
| assigned\_group\_names | Group display names assigned to the application (looked up in the identity store). | `list(string)` | `[]` | no |
| assigned\_groups | Identity store group ids assigned to the application. | `list(string)` | `[]` | no |
| assigned\_user\_names | User names assigned to the application (looked up in the identity store). | `list(string)` | `[]` | no |
| assigned\_users | Identity store user ids assigned to the application. | `list(string)` | `[]` | no |
| create\_identity\_store\_role | Create a role the gate assumes to read users and group memberships of the identity store (identity\_store\_role\_arn of the root module). Identity Center SAML assertions carry no group. | `bool` | `false` | no |
| gate\_role\_arns | Gate function roles allowed to assume the identity store reader role (output lambda\_role\_arn of the root module). | `list(string)` | `[]` | no |
| identity\_store\_role\_external\_id | External id required to assume the identity store reader role (optional). | `string` | `null` | no |
| identity\_store\_role\_name | Name of the identity store reader role. | `string` | `"dns-gate-identity-store-reader"` | no |
| permissions\_boundary\_arn | Permissions boundary of the identity store reader role (optional). | `string` | `null` | no |
| saml\_audience | SAML audience (SP entity id) of the gate. Must equal the entity id configured in the gate. Null: https://<gate\_domain\_name>/auth/saml/metadata. | `string` | `null` | no |
| tags | Tags applied to the application and the role. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| application\_arn | ARN of the Identity Center application (application\_arn) |
| identity\_store\_id | ID of the identity store |
| identity\_store\_role\_arn | Role the gate assumes to read the identity store (identity\_store\_role\_arn of the root module), null when not created |
| instance\_arn | ARN of the Identity Center instance |
| saml\_acs\_url | ACS URL to set in the application |
| saml\_audience | SAML audience (SP entity id) to set in the application and in the gate |
| saml\_configuration\_instructions | Console steps completing the SAML configuration (not available through the API) |
<!-- END_TF_DOCS -->
