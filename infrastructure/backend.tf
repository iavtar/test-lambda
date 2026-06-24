terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "gfj-prod-tfstate"
    key            = "test101.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "dev-terraform-lock"
    encrypt        = true
  }
}