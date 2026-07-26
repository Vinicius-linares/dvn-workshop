data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.remote_state.name_prefix}-${var.remote_state.purpose_suffix}-${data.aws_caller_identity.current.account_id}-${var.region}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = local.bucket_name
  }
}
