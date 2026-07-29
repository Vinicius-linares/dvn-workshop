output "eks_cluster_name" {
  description = "The name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_arn" {
  description = "The ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "eks_cluster_endpoint" {
  description = "The endpoint URL for the EKS cluster API server."
  value       = aws_eks_cluster.this.endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the EKS cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "eks_cluster_oidc_issuer_url" {
  description = "The OIDC issuer URL of the EKS cluster, used for IRSA configuration."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "eks_cluster_security_group_id" {
  description = "The cluster security group ID created by EKS."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "eks_cluster_version" {
  description = "The Kubernetes version running on the EKS cluster."
  value       = aws_eks_cluster.this.version
}

output "eks_cluster_role_arn" {
  description = "The ARN of the IAM role used by the EKS cluster control plane."
  value       = aws_iam_role.cluster.arn
}

output "eks_node_group_role_arn" {
  description = "The ARN of the IAM role used by the EKS managed node group."
  value       = aws_iam_role.node.arn
}

output "eks_node_group_arn" {
  description = "The ARN of the EKS managed node group."
  value       = aws_eks_node_group.this.arn
}

output "eks_openid_connect_provider_arn" {
  description = "The ARN of the IAM OIDC provider, used to configure IRSA for workloads."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "eks_openid_connect_provider_url" {
  description = "The URL of the IAM OIDC provider (without https:// prefix), used in IAM role trust policies for IRSA."
  value       = aws_iam_openid_connect_provider.eks.url
}

output "ecr_repository_urls" {
  description = "Map of ECR repository name to its repository URL, used to tag and push container images."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "ecr_repository_arns" {
  description = "Map of ECR repository name to its ARN."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}
