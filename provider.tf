terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # These values will be configured during terraform init
    # terraform init -backend-config="bucket=<your-bucket-name>" \
    #                -backend-config="key=devsecops-pipeline/terraform.tfstate" \
    #                -backend-config="region=<your-region>"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "DevSecOps-Pipeline"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}
