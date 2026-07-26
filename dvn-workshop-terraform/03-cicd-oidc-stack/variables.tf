variable "region" {
  description = "AWS region where the CI/CD OIDC stack is deployed."
  type        = string
}

variable "default_tags" {
  description = "Tags applied to every resource in this stack via the AWS provider default_tags block."
  type        = map(string)
}

variable "github_oidc" {
  description = "Configuration for the GitHub Actions OIDC federation: provider URL, audience list, subject claim used in the trust policy condition, and IAM role name. No value is hard-coded in the resource blocks; all concrete values live in terraform.tfvars."
  type = object({
    provider_url  = string
    audiences     = list(string)
    subject_claim = string
    role_name     = string
  })
}
