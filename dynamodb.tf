# -----------------------------------------------------------------------------
# Store table (single-table layout of internal/store/dynamodb*.go)
# pk (S) / sk (S), no secondary index, TTL on "ttl" (N, unix seconds)
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name                        = local.table_name
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "pk"
  range_key                   = "sk"
  deletion_protection_enabled = var.dynamodb_deletion_protection

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = var.dynamodb_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = var.dynamodb_kms_key_arn != null
    kms_key_arn = var.dynamodb_kms_key_arn
  }

  tags = var.tags
}
