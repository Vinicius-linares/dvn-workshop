variable "region" {
  description = "AWS region where the EKS cluster stack is deployed."
  type        = string
}

variable "default_tags" {
  description = "Tags applied to every resource in this stack via the AWS provider default_tags block."
  type        = map(string)
}

variable "eks" {
  description = "EKS cluster definition including name, Kubernetes version, networking configuration, control plane logging, access settings, node group sizing, and access entries for additional principals. No value is hard-coded in the resource blocks; all concrete values live in terraform.tfvars."
  type = object({
    name                                        = string
    version                                     = string
    authentication_mode                         = string
    bootstrap_cluster_creator_admin_permissions = bool
    enabled_cluster_log_types                   = list(string)
    log_retention_in_days                       = number
    endpoint_private_access                     = bool
    endpoint_public_access                      = bool
    public_access_cidrs                         = list(string)

    node_group = object({
      name            = string
      capacity_type   = string
      instance_types  = list(string)
      desired_size    = number
      min_size        = number
      max_size        = number
      max_unavailable = number
    })

    access_entries = list(object({
      principal_arn = string
      policy_arn    = string
    }))
  })
}

variable "ecr_repositories" {
  description = "List of ECR repositories to create, each with its own name, tag mutability, and image scanning configuration. No value is hard-coded in the resource blocks; all concrete values live in terraform.tfvars."
  type = list(object({
    name                 = string
    image_tag_mutability = string
    scan_on_push         = bool
  }))
}
