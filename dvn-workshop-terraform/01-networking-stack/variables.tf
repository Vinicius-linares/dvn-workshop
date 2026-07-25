variable "region" {
  description = "AWS region where the networking stack is deployed."
  type        = string
}

variable "vpc" {
  description = "VPC definition including name, CIDR block, subnet configuration grouped by type, and the names of the gateways and route tables. Each subnet carries its own name, CIDR, and availability zone so resources can iterate with for_each. No resource name or value is hard-coded in the resource blocks."
  type = object({
    name = string
    cidr = string
    public_subnets = list(object({
      name              = string
      cidr              = string
      availability_zone = string
    }))
    private_subnets = list(object({
      name              = string
      cidr              = string
      availability_zone = string
    }))
    internet_gateway_name    = string
    nat_eip_name             = string
    nat_gateway_name         = string
    public_route_table_name  = string
    private_route_table_name = string
  })
}

variable "default_route_cidr" {
  description = "Destination CIDR used for the default egress routes (public route table via IGW, private route table via NAT gateway)."
  type        = string
  default     = "0.0.0.0/0"
}

variable "default_tags" {
  description = "Tags applied to every resource in this stack via the AWS provider default_tags block."
  type        = map(string)
}
