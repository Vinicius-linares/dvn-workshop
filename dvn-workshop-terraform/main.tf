terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Create a VPC
resource "aws_vpc" "this" {
  cidr_block = var.vpc.cidr_block
  tags = {
    Name = "dvn-bigode-vpc"
  }
}