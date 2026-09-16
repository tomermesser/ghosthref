terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  // currently for saving costs, I save the state locally and not in s3.. 
}

provider "aws" {
  region = var.region
}
