data "terraform_remote_state" "networking" {
  backend = "s3"

  config = {
    bucket = "dvn-bigode-tfstate-654654554686-us-east-1"
    key    = "01-networking-stack/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  vpc_id             = data.terraform_remote_state.networking.outputs.vpc_id
  private_subnet_ids = values(data.terraform_remote_state.networking.outputs.private_subnet_ids)
}
