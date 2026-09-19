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


# Infrastructure: aws_vpc, aws_subnet, aws_internet_gateway, aws_route_table, aws_route_table_association (5
# networking pieces), 3 security groups, 3 EC2 instances, and budget alarm