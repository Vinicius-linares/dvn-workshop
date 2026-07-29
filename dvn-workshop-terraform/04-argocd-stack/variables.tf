variable "region" {
  description = "AWS region where the ArgoCD stack is deployed."
  type        = string
}

variable "default_tags" {
  description = "Tags applied to every AWS resource in this stack via the provider default_tags block."
  type        = map(string)
}

variable "argocd" {
  description = "Configuration for the ArgoCD installation and the GitOps Application. No value is hard-coded in the resource blocks; all concrete values live in terraform.tfvars."
  type = object({
    chart_version = string
    namespace     = string
    application = object({
      name                = string
      repo_url            = string
      path                = string
      target_revision     = string
      dest_namespace      = string
      automated_prune     = bool
      automated_self_heal = bool
    })
  })
}
