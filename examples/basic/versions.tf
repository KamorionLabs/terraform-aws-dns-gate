terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

# Gate account (shared services)
provider "aws" {
  alias  = "shared"
  region = "eu-west-3"

  assume_role {
    role_arn = "arn:aws:iam::111111111111:role/terraform"
  }
}

# Account owning the Route53 hosted zones
provider "aws" {
  alias  = "network"
  region = "eu-west-3"

  assume_role {
    role_arn = "arn:aws:iam::222222222222:role/terraform"
  }
}
