# terraform-aws-dns-gate

Terraform module running [dns-gate](https://github.com/KamorionLabs/dns-gate), the security gateway in front of DNS provider APIs (EuroDNS, Route53), on AWS Lambda behind an API Gateway HTTP API, with its DynamoDB store, configuration, secrets, maintenance schedule and alarms.

Two sub-modules complete it:

- [`modules/route53-access`](modules/route53-access): the role the gate assumes in the account owning the Route53 hosted zones, limited to those zones, with apex NS/SOA and reserved names denied.
- [`modules/identity-center-saml-app`](modules/identity-center-saml-app): the IAM Identity Center custom SAML application for the human login, and an optional identity store reader role.

## Architecture

```
                        Users (browser, CLI, MCP)      CI pipelines (OIDC)
                                     │                         │
                                     ▼                         ▼
                        https://dns-gate.example.com  (Route53 alias, ACM)
                                     │
                        ┌────────────▼─────────────┐
                        │ API Gateway HTTP API     │  $default route, payload 2.0,
                        │ (throttling, access logs)│  30 s per request
                        └────────────┬─────────────┘
                                     │
 EventBridge Scheduler ──────────────▼──────────────────────────────────────────┐
 rate(5 minutes)          ┌──────────────────────────┐                          │
 {"dns_gate_task":        │ Lambda dns-gate          │── DynamoDB (store: ownership,
  "maintenance"}  ───────▶│ provided.al2023 arm64    │    locks, audit, policy, plans)
                          │ bootstrap                │── SSM parameter / S3 (config)
                          └──────┬────────────┬──────┘── Secrets Manager (keys)
       Shared services account   │            │
 ────────────────────────────────┼────────────┼──────────────────────────────────
       DNS account               │ sts:AssumeRole (+ external id)
                                 ▼            │
                      role dns-gate-route53   │       Identity Center account
                      Route53 hosted zones    └──────▶ identity store reader role
                      (apex NS/SOA denied)            (optional, groups)
```

- **One function** serves the HTTP API and the maintenance task (reconcile, zone discovery, garbage collection), invoked every 5 minutes by EventBridge Scheduler with `{"dns_gate_task":"maintenance"}`. Asynchronous invocations are never retried (scheduler target and `aws_lambda_function_event_invoke_config`): the task is idempotent and runs must not stack.
- **Store**: one DynamoDB table (`pk`/`sk`, no secondary index, TTL on `ttl`), on-demand, point-in-time recovery, deletion protection, AWS owned or customer managed key.
- **Configuration**: `config_yaml` goes to an SSM String parameter (default) or an S3 object, passed as `DNS_GATE_CONFIG_URI`. `DNS_GATE_CONFIG_VERSION` (sha256 of the YAML) changes with it, so a configuration change replaces the execution environments.
- **Secrets**: one Secrets Manager secret, a JSON object whose keys are environment variable names (`DNS_GATE_SESSION_KEY`, `DNS_GATE_TOKEN_SIGNING_KEY`, `DNS_GATE_SAML_SP_KEY`, `EURODNS_API_KEY`...), passed as `DNS_GATE_SECRETS_ARN`. The gate loads it before parsing the configuration; a variable already set in the environment wins over the same key of the secret.
- **Cross-account**: the function role may only assume the roles listed in `route53_role_arns` and `identity_store_role_arn`.

## Usage

The gate runs in a shared services account, the hosted zones live in a DNS account. A full example is in [`examples/basic`](examples/basic).

```hcl
module "route53_access" {
  source    = "github.com/KamorionLabs/terraform-aws-dns-gate//modules/route53-access"
  providers = { aws = aws.network }

  gate_role_arns      = [module.dns_gate.lambda_role_arn]
  external_id         = "dns-gate-example"
  hosted_zone_ids     = ["Z0123456789EXAMPLEAAA", "Z0123456789EXAMPLEBBB"]
  denied_record_names = ["www.example.com", "*.k8s.example.com"]
}

module "dns_gate" {
  source    = "github.com/KamorionLabs/terraform-aws-dns-gate"
  providers = { aws = aws.shared }

  name            = "dns-gate"
  lambda_zip_path = "${path.module}/dns-gate_0.6.0_lambda_arm64.zip"

  config_yaml = templatefile("${path.module}/config.yaml.tftpl", {
    table           = "dns-gate"
    assume_role_arn = module.route53_access.role_arn
    external_id     = "dns-gate-example"
  })
  route53_role_arns = [module.route53_access.role_arn]

  domain_name        = "dns-gate.example.com"
  create_certificate = true

  alarm_sns_topic_arn = "arn:aws:sns:eu-west-3:111111111111:ops-alerts"
}

module "saml_app" {
  source    = "github.com/KamorionLabs/terraform-aws-dns-gate//modules/identity-center-saml-app"
  providers = { aws = aws.management }

  gate_domain_name     = "dns-gate.example.com"
  assigned_group_names = ["dns-admins"]
}
```

### Gate configuration

The module does not generate the YAML: write it (with `templatefile`) and keep in mind:

- `store.type: dynamodb` and `store.dynamodb.table` = output `dynamodb_table_name` (default: `name`).
- Each `providers[].route53` entry: `region`, `assume_role_arn` (output `role_arn` of `route53-access`), `external_id`, `hosted_zones`, `include_private`. Its role must also be in `route53_role_arns`.
- `lock.wait` at most **20 s**: API Gateway cuts every HTTP request at 30 s, a request waiting longer for a zone lock would end in a 503 from API Gateway instead of the gate's `zone_locked`.
- `listen.trusted_proxies` stays empty: behind API Gateway the client address comes from the request context, not from `X-Forwarded-For`.
- No secret in the YAML: the parameter is a plain `String`.

The function accepts other configuration sources through `config_uri` (and `config_yaml = null`): a file path or `file://` URI inside the zip, `s3://bucket/key` or `ssm:/name` (a `SecureString` is decrypted: grant `kms:Decrypt` on its CMK with `lambda_additional_policy_json`). The gate reads at most 4 MiB.

#### SSM or S3

| | `config_storage = "ssm"` (default) | `config_storage = "s3"` |
|---|---|---|
| Size | 4 KB Standard (free), 8 KB Advanced (0.05 USD/month), tier chosen automatically | up to 4 MiB (gate limit) |
| Needs | nothing | an existing bucket (`config_s3_bucket`), optionally SSE-KMS (`config_s3_kms_key_arn`) |
| History | parameter versions | bucket versioning, if enabled |

Use SSM until the configuration outgrows 8 KB (large inline policies, many virtual keys), then S3.

### Custom domain and certificate

- `certificate_arn`: an existing ACM certificate in the region of the API.
- `create_certificate = true`: the module requests a DNS-validated certificate and waits for it. With `certificate_validation_zone_id` the validation record is created in that zone (same account as the module's provider). When the zone lives in another account, create the record from output `certificate_validation_record` with that account's provider (see the example): Terraform creates it while the module waits, in the same apply.
- The gate record itself (alias `A`/`AAAA` to `domain_target_domain_name` / `domain_hosted_zone_id`) is created by the caller, in whatever account owns the zone.
- With a custom domain the `execute-api` endpoint is disabled (`disable_execute_api_endpoint`), so the SAML ACS URL and cookies always match the public name.

### Secrets

The module creates the secret with a placeholder (`REPLACE_ME` for each key of `secret_placeholder_keys`) and ignores later changes of its value: the real values never enter the Terraform state. Set them once after the first apply:

```bash
# values generated locally, never echoed
jq -n \
  --arg session "$(openssl rand -hex 32)" \
  --arg signing "$(openssl rand -hex 32)" \
  --rawfile spkey sp-key.pem \
  '{DNS_GATE_SESSION_KEY: $session, DNS_GATE_TOKEN_SIGNING_KEY: $signing, DNS_GATE_SAML_SP_KEY: $spkey}' \
  > secrets.json
aws secretsmanager put-secret-value --secret-id dns-gate --secret-string file://secrets.json --region eu-west-3
rm secrets.json
```

New values are read by new execution environments only: force them with a configuration change or `aws lambda update-function-configuration` (any environment change). Do not set the secret keys in `lambda_environment_variables`: an environment variable wins over the secret.

### Route53 access

`modules/route53-access` creates the role assumed by the gate in the DNS account:

- read: `ListHostedZones`, `ListHostedZonesByName` (account-wide, as Route53 requires), `GetHostedZone`, `ListResourceRecordSets`, `GetChange`;
- write: `ChangeResourceRecordSets` on the listed zones only;
- deny (unless `protect_apex_ns_soa = false`): any change batch naming the zone apex **and** an `NS` or `SOA` type (conditions `route53:ChangeResourceRecordSetsNormalizedRecordNames` and `route53:ChangeResourceRecordSetsRecordTypes`). Both conditions apply to the whole batch, so a batch mixing an apex record and a delegation `NS` elsewhere is refused too;
- deny any change naming one of `denied_record_names` (IAM `StringLike`, `*` and `?` wildcards): records owned by other tools (Terraform stacks, external-dns...).

These denies hold even if the gate policy is wrong or the gate is compromised. The inline policy grows by about 350 characters per zone (limit 10 240): split the zones over several roles beyond about 25 zones.

### Identity Center SAML application

`modules/identity-center-saml-app` manages the assignments of the dns-gate SAML application in the account managing IAM Identity Center. The Identity Center API cannot create a custom SAML 2.0 application (`CreateApplication` refuses the `custom-saml` provider) nor set its metadata and attribute mappings: create it in the console following output `saml_configuration_instructions`, then set `application_arn` and apply (users and groups assigned; a SAML application always requires assignment). Until then the module manages no assignment. Console values:

- ACS URL: `https://<domain>/auth/saml/acs`
- SAML audience: `https://<domain>/auth/saml/metadata` by default (`saml_audience`), the same value as the gate's SP entity id
- attribute mappings: Subject `${user:email}` (emailAddress), `email` = `${user:email}`, `name` = `${user:name}`
- IdP metadata (URL or file) copied into the gate configuration

Identity Center sends no group in the assertion. With `create_identity_store_role = true` the module also creates a read-only identity store role for the gate (`identity_store_role_arn` of the root module).

### Audit export

The gate writes one JSON line per audit event (`"type": "audit"`) to its log group,
next to the application logs (see [AUDIT.md](https://github.com/KamorionLabs/dns-gate/blob/main/docs/AUDIT.md)
for the schema, the ECS/OCSF formats and the hash chain). `audit_export` adds a
subscription filter on the function log group, `{ $.type = "audit" }` by default,
towards a SIEM or an archive:

```hcl
module "dns_gate" {
  # ...
  audit_export = {
    destination_arn = aws_kinesis_firehose_delivery_stream.audit.arn
  }
}
```

| Destination (`destination_arn`) | What the module adds |
|---|---|
| Kinesis Data Firehose delivery stream (to S3, Splunk, Datadog, OpenSearch, an HTTP endpoint) | IAM role assumed by CloudWatch Logs with `firehose:PutRecord(Batch)` on the stream, unless `role_arn` is given |
| Kinesis data stream | IAM role with `kinesis:PutRecord(s)` on the stream, unless `role_arn` is given; `distribution` (`ByLogStream` or `Random`) |
| Lambda function | `lambda:InvokeFunction` permission for CloudWatch Logs, limited to the log group |
| CloudWatch Logs destination (central logging account) | Nothing: the destination policy must allow this account |

The role trusts `logs.amazonaws.com` for this account and region only (`aws:SourceArn`).
`filter_pattern` narrows the export (for example `{ $.type = "audit" && $.decision != "allow" }`)
and `filter_name` names the filter (default `<name>-audit`). A log group accepts two
subscription filters. With Firehose to S3, enable the CloudWatch Logs decompression and
message extraction processors of the delivery stream, so that objects hold the original
JSON lines (readable by Athena and `dns-gate audit verify`), and Object Lock on the bucket.

## Upgrade

The release assets are `dns-gate_<version>_lambda_arm64.zip` (no `v`: tag `v0.6.0` gives `dns-gate_0.6.0_lambda_arm64.zip`) and a `.sha256` file in `sha256sum` format.

```bash
VERSION=0.6.0
gh release download "v${VERSION}" -R KamorionLabs/dns-gate -p "dns-gate_${VERSION}_lambda_arm64.zip*"
sha256sum -c "dns-gate_${VERSION}_lambda_arm64.zip.sha256"   # shasum -a 256 -c on macOS
```

1. Local zip: point `lambda_zip_path` at the new file. S3: upload it under a new key (`aws s3 cp dns-gate_${VERSION}_lambda_arm64.zip s3://<bucket>/dns-gate/`) and change `lambda_s3_key`.
2. Read the release notes for configuration changes (unknown fields stop the gate at startup) and apply them to `config_yaml` in the same change.
3. `terraform plan`: only `aws_lambda_function.this` (and the configuration, if changed) should move. Apply.
4. Check: `curl -fsS https://<domain>/healthz`, the function logs, and one maintenance run (`maintenance_invoke_command` output).

Rollback: the previous zip path or S3 key, then apply. The store schema is backward compatible within a major version; check the release notes before going back across a store migration.

## Costs

Order of magnitude for one gate, a few zones and moderate traffic (eu-west-3, before free tier):

| Item | Monthly cost |
|---|---|
| Lambda (arm64, 512 MB): maintenance every 5 min (8 640 runs) + requests | ~0 to 0.50 USD (mostly within the free tier) |
| API Gateway HTTP API (~1 USD per million requests) | cents |
| DynamoDB on-demand + PITR (a few MB) | < 1 USD |
| Secrets Manager | 0.40 USD per secret (+ 0.05 USD per 10 000 calls, cold starts only) |
| SSM parameter | 0 (Standard) or 0.05 USD (Advanced) |
| CloudWatch Logs (ingestion ~0.76 USD/GB, retention `log_retention_days`) | cents to 1 USD |
| CloudWatch alarms (3, when enabled) | 0.30 USD |
| EventBridge Scheduler | 0 (14 million free invocations) |
| Customer managed KMS keys (optional) | 1 USD per key |

Expect 1 to 3 USD per month without customer managed keys.

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
| [aws_acm_certificate.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_apigatewayv2_api.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api) | resource |
| [aws_apigatewayv2_api_mapping.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api_mapping) | resource |
| [aws_apigatewayv2_domain_name.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_domain_name) | resource |
| [aws_apigatewayv2_integration.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_integration) | resource |
| [aws_apigatewayv2_route.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route) | resource |
| [aws_apigatewayv2_stage.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_stage) | resource |
| [aws_cloudwatch_log_group.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_subscription_filter.audit_export](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_subscription_filter) | resource |
| [aws_cloudwatch_metric_alarm.api_5xx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.lambda_errors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.lambda_throttles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_dynamodb_table.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_iam_role.audit_export](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.audit_export](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.lambda_additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_function.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function_event_invoke_config.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function_event_invoke_config) | resource |
| [aws_lambda_permission.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_lambda_permission.audit_export](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_route53_record.certificate_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_s3_object.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_scheduler_schedule.maintenance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_secretsmanager_secret.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.placeholder](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_ssm_parameter.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.audit_export](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.audit_export_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lambda_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.scheduler_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Base name for every resource (e.g. 'dns-gate'). Also the default DynamoDB table name and SSM parameter prefix. | `string` | n/a | yes |
| alarm\_api\_5xx\_threshold | Number of 5xx responses over 5 minutes raising the API alarm. | `number` | `5` | no |
| alarm\_sns\_topic\_arn | SNS topic receiving the alarms (Lambda errors and throttles, API 5xx). Null creates no alarm. | `string` | `null` | no |
| api\_throttling\_burst\_limit | Default route burst limit of the HTTP API stage. | `number` | `100` | no |
| api\_throttling\_rate\_limit | Default route steady-state rate limit (requests per second) of the HTTP API stage. | `number` | `50` | no |
| audit\_export | Forward the audit events of the function log group to a SIEM or an archive: a subscription filter (default pattern { $.type = "audit" }) towards destination\_arn, a Kinesis Data Firehose delivery stream, a Kinesis data stream, a Lambda function or a CloudWatch Logs destination (cross-account). For Firehose and Kinesis the module creates the role CloudWatch Logs assumes unless role\_arn is given; for a Lambda function it adds the invoke permission. distribution (ByLogStream or Random) applies to Kinesis data streams only. Null exports nothing. | <pre>object({<br/>    destination_arn = string<br/>    role_arn        = optional(string)<br/>    filter_name     = optional(string)<br/>    filter_pattern  = optional(string, "{ $.type = \"audit\" }")<br/>    distribution    = optional(string, "ByLogStream")<br/>  })</pre> | `null` | no |
| certificate\_arn | ACM certificate (same region) for domain\_name. Exclusive with create\_certificate. | `string` | `null` | no |
| certificate\_validation\_zone\_id | Route53 zone (in the account of the default provider) receiving the ACM validation record. Null when the zone lives in another account: create the record from output certificate\_validation\_record, the module waits for the certificate. | `string` | `null` | no |
| config\_s3\_bucket | Existing S3 bucket receiving the configuration object when config\_storage = 's3'. | `string` | `null` | no |
| config\_s3\_key | S3 key of the configuration object (default: <name>/config.yaml). | `string` | `null` | no |
| config\_s3\_kms\_key\_arn | KMS key encrypting the configuration bucket (SSE-KMS), granted kms:Decrypt to the function. Null for SSE-S3. | `string` | `null` | no |
| config\_ssm\_parameter\_name | Name of the SSM parameter holding the configuration (default: /<name>/config). | `string` | `null` | no |
| config\_storage | Where the module stores config\_yaml: 'ssm' (SSM parameter, Advanced tier above 4 KB, max 8 KB) or 's3' (object in config\_s3\_bucket). | `string` | `"ssm"` | no |
| config\_uri | Configuration managed outside the module: a file path or file:// URI inside the zip, s3://bucket/key or ssm:/name (SecureString accepted). When set, config\_yaml must be null; grant read access (and kms:Decrypt for a CMK) with lambda\_additional\_policy\_json. | `string` | `null` | no |
| config\_yaml | dns-gate configuration (YAML). Its store section must point at the DynamoDB table of the module (output dynamodb\_table\_name). Null when config\_uri points at a configuration managed elsewhere. | `string` | `null` | no |
| create\_certificate | Create an ACM certificate for domain\_name with DNS validation. | `bool` | `false` | no |
| create\_secret | Create the Secrets Manager secret (JSON, keys = environment variable names) with a placeholder value to replace out of Terraform. False to use secret\_arn. | `bool` | `true` | no |
| disable\_execute\_api\_endpoint | Disable the default execute-api endpoint (null: disabled when domain\_name is set, so that every request reaches the gate under its public name). | `bool` | `null` | no |
| domain\_name | Custom domain of the gate (e.g. 'dns-gate.example.com'). Null keeps the execute-api endpoint only. | `string` | `null` | no |
| dynamodb\_deletion\_protection | Enable deletion protection on the table. | `bool` | `true` | no |
| dynamodb\_kms\_key\_arn | Customer managed KMS key of the table (null: AWS owned key). | `string` | `null` | no |
| dynamodb\_point\_in\_time\_recovery | Enable point-in-time recovery (35 days of continuous backups). | `bool` | `true` | no |
| dynamodb\_table\_name | Name of the store table (default: <name>). The gate configuration must use the same name in store.dynamodb.table. | `string` | `null` | no |
| enable\_maintenance\_schedule | Create the EventBridge Scheduler schedule invoking the maintenance task (reconcile, discovery, garbage collection). | `bool` | `true` | no |
| iam\_permissions\_boundary\_arn | Permissions boundary applied to the IAM roles created by the module (optional). | `string` | `null` | no |
| identity\_store\_role\_arn | IAM role the gate assumes to read users and group memberships in the IAM Identity Center identity store (optional, see modules/identity-center-saml-app). | `string` | `null` | no |
| lambda\_additional\_policy\_json | Extra IAM policy document (JSON) attached to the function role, as an escape hatch for permissions this module does not grant. | `string` | `null` | no |
| lambda\_environment\_variables | Extra environment variables of the function. DNS\_GATE\_CONFIG\_URI, DNS\_GATE\_SECRETS\_ARN and DNS\_GATE\_CONFIG\_VERSION are set by the module and cannot be overridden. A variable set here wins over the same key of the secret: never put secrets here, nor the keys of the secret. | `map(string)` | `{}` | no |
| lambda\_memory\_size | Lambda memory in MB (CPU scales with it). | `number` | `512` | no |
| lambda\_reserved\_concurrent\_executions | Reserved concurrency of the function. Caps the parallel calls to the DNS provider APIs and the concurrent zone writes. Null: unreserved. | `number` | `5` | no |
| lambda\_s3\_bucket | S3 bucket holding the Lambda zip (same region as the function). Exclusive with lambda\_zip\_path. | `string` | `null` | no |
| lambda\_s3\_key | S3 key of the Lambda zip. Put the version in the key (e.g. 'dns-gate/dns-gate\_1.4.0\_lambda\_arm64.zip') so that an upgrade changes it. | `string` | `null` | no |
| lambda\_s3\_object\_version | Object version of the Lambda zip in a versioned bucket (optional). | `string` | `null` | no |
| lambda\_timeout | Lambda timeout in seconds, sized for the maintenance task (reconcile of every zone). HTTP requests are cut at 30 s by API Gateway whatever this value. | `number` | `120` | no |
| lambda\_vpc\_security\_group\_ids | Security groups of the function when lambda\_vpc\_subnet\_ids is set (egress HTTPS only is enough). | `list(string)` | `[]` | no |
| lambda\_vpc\_subnet\_ids | Private subnets to run the function in (optional). Needed for a fixed egress IP through a NAT gateway, e.g. when the EuroDNS API key is IP-restricted. | `list(string)` | `[]` | no |
| lambda\_zip\_path | Local path of the release asset dns-gate\_<version>\_lambda\_arm64.zip. Exclusive with lambda\_s3\_bucket/lambda\_s3\_key. | `string` | `null` | no |
| log\_retention\_days | Retention of the Lambda and API Gateway access log groups. | `number` | `30` | no |
| logs\_kms\_key\_arn | KMS key encrypting the log groups (optional, its key policy must allow CloudWatch Logs). | `string` | `null` | no |
| maintenance\_schedule\_expression | Schedule expression of the maintenance task. | `string` | `"rate(5 minutes)"` | no |
| route53\_role\_arns | IAM roles the gate assumes to manage Route53 hosted zones in other accounts (see modules/route53-access). Must match providers[].route53.assume\_role\_arn in the gate configuration. | `list(string)` | `[]` | no |
| secret\_arn | Existing Secrets Manager secret (JSON, keys = environment variable names) when create\_secret = false. | `string` | `null` | no |
| secret\_kms\_key\_arn | Customer managed KMS key of the secret (null: aws/secretsmanager). Also used to grant kms:Decrypt for an existing secret. | `string` | `null` | no |
| secret\_name | Name of the created secret (default: <name>). | `string` | `null` | no |
| secret\_placeholder\_keys | Keys of the placeholder JSON written once at creation (values 'REPLACE\_ME'). Later changes of the value are ignored by Terraform. | `list(string)` | <pre>[<br/>  "DNS_GATE_SESSION_KEY",<br/>  "DNS_GATE_TOKEN_SIGNING_KEY",<br/>  "DNS_GATE_SAML_SP_KEY"<br/>]</pre> | no |
| secret\_recovery\_window\_in\_days | Recovery window of the created secret when it is deleted (0 deletes immediately). | `number` | `30` | no |
| tags | Tags applied to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| api\_endpoint | Default execute-api endpoint (disabled when a custom domain is set, unless disable\_execute\_api\_endpoint = false) |
| api\_id | ID of the HTTP API |
| audit\_export\_role\_arn | Role CloudWatch Logs assumes to deliver the audit events (created or given), null without audit\_export or for a Lambda or Logs destination |
| certificate\_arn | ACM certificate of the custom domain |
| certificate\_validation\_record | DNS record validating the created certificate ({name, type, value}), to create when the zone is in another account |
| config\_ssm\_parameter\_name | SSM parameter holding the configuration (null unless config\_storage = ssm) |
| config\_ssm\_parameter\_tier | Tier of the configuration parameter (Advanced above 4 KB) |
| config\_uri | DNS\_GATE\_CONFIG\_URI given to the function |
| domain\_hosted\_zone\_id | Hosted zone id of the target, for an alias record |
| domain\_target\_domain\_name | Target of the gate DNS record (alias A/AAAA, or CNAME) |
| dynamodb\_table\_arn | ARN of the store table |
| dynamodb\_table\_name | Store table: store.dynamodb.table in the gate configuration |
| lambda\_function\_arn | ARN of the gate function |
| lambda\_function\_name | Name of the gate function |
| lambda\_log\_group\_name | Log group of the function |
| lambda\_role\_arn | ARN of the function role: trusted principal of the route53-access and identity store roles |
| lambda\_role\_name | Name of the function role |
| maintenance\_invoke\_command | AWS CLI command running the maintenance task once |
| maintenance\_schedule\_arn | ARN of the maintenance schedule |
| saml\_acs\_url | SAML Assertion Consumer Service URL to declare in IAM Identity Center |
| secret\_arn | Secrets Manager secret read at startup (DNS\_GATE\_SECRETS\_ARN) |
| url | Public URL of the gate |
<!-- END_TF_DOCS -->

## License

MIT, see [LICENSE](LICENSE).

## Authors

Kamorion - [https://kamorion.com](https://kamorion.com)
