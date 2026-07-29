data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket = "dvn-tfstate-934384776856-us-east-1"
    key    = "02-eks-cluster-stack/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  ecr_repository_arns = values(data.terraform_remote_state.eks.outputs.ecr_repository_arns)
}
