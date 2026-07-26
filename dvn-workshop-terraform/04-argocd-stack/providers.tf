provider "aws" {
  region = var.region

  default_tags {
    tags = var.default_tags
  }
}

# Helm provider uses exec-based auth so the EKS token is resolved at runtime
# and never persisted in Terraform state.
provider "helm" {
  kubernetes = {
    host                   = local.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(local.eks_cluster_ca_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.eks_cluster_name, "--region", var.region]
    }
  }
}

# Kubernetes provider also uses exec-based auth for the same reason.
provider "kubernetes" {
  host                   = local.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(local.eks_cluster_ca_data)

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.eks_cluster_name, "--region", var.region]
  }
}
