# route53-access

Role assumed by dns-gate in the account owning the Route53 hosted zones: read and change records of the listed zones only, never the apex NS/SOA nor the reserved names. See the root README, section Route53 access.

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
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.route53](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| gate\_role\_arns | IAM roles allowed to assume this role: the gate function role (output lambda\_role\_arn of the root module). | `list(string)` | n/a | yes |
| hosted\_zone\_ids | Route53 hosted zones (ids, without the /hostedzone/ prefix) the gate may read and change. | `list(string)` | n/a | yes |
| denied\_record\_names | Record names the gate may never change, in any of the zones (names reserved for other tools, e.g. records managed by Terraform). Lowercase, without trailing dot; '*' and '?' are wildcards (IAM StringLike), e.g. 'www.example.com' or '*.internal.example.com'. | `list(string)` | `[]` | no |
| external\_id | External id required in the AssumeRole call (providers[].route53.external\_id in the gate configuration). Null: no external id. | `string` | `null` | no |
| max\_session\_duration | Maximum session duration of the role, in seconds. | `number` | `3600` | no |
| permissions\_boundary\_arn | Permissions boundary of the role (optional). | `string` | `null` | no |
| protect\_apex\_ns\_soa | Deny changes touching the NS and SOA records of each zone apex. | `bool` | `true` | no |
| role\_name | Name of the role assumed by the gate. | `string` | `"dns-gate-route53"` | no |
| tags | Tags applied to the role. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| external\_id | External id required by the role (null: none) |
| gate\_provider\_config | route53 block of a gate provider entry (providers[].route53), to render into the gate configuration |
| hosted\_zones | Managed zones: id => apex name |
| policy\_json | Inline policy of the role (for review) |
| role\_arn | ARN of the role: providers[].route53.assume\_role\_arn in the gate configuration, and route53\_role\_arns of the root module |
| role\_name | Name of the role |
<!-- END_TF_DOCS -->
