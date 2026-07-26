data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket = "dvn-bigode-tfstate-654654554686-us-east-1"
    key    = "02-eks-cluster-stack/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  eks_cluster_name     = data.terraform_remote_state.eks.outputs.eks_cluster_name
  eks_cluster_endpoint = data.terraform_remote_state.eks.outputs.eks_cluster_endpoint
  eks_cluster_ca_data  = data.terraform_remote_state.eks.outputs.eks_cluster_certificate_authority_data
}
