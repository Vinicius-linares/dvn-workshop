output "state_s3_bucket_name" {
  description = "Name of the S3 bucket used as Terraform remote state backend."
  value       = aws_s3_bucket.state.id
}

output "state_s3_bucket_arn" {
  description = "ARN of the S3 bucket used as Terraform remote state backend."
  value       = aws_s3_bucket.state.arn
}

output "state_s3_bucket_region" {
  description = "AWS region where the Terraform remote state S3 bucket resides."
  value       = aws_s3_bucket.state.bucket_region
}
