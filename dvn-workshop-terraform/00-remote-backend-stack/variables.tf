variable "region" {
  description = "AWS region where the remote backend stack is deployed."
  type        = string
}

variable "remote_state" {
  description = "Configuration for the Terraform remote state S3 bucket: name prefix, purpose suffix, and flags for versioning and encryption. The actual bucket name is derived in locals from these values combined with the AWS account ID and region to guarantee global uniqueness."
  type = object({
    name_prefix        = string
    purpose_suffix     = string
    versioning_enabled = bool
    sse_algorithm      = string
  })
}

variable "default_tags" {
  description = "Tags applied to every resource in this stack via the AWS provider default_tags block."
  type        = map(string)
}
