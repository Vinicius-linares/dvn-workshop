resource "aws_eks_cluster" "this" {
  name     = var.eks.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.eks.version

  vpc_config {
    subnet_ids              = local.private_subnet_ids
    endpoint_private_access = var.eks.endpoint_private_access
    endpoint_public_access  = var.eks.endpoint_public_access
    public_access_cidrs     = var.eks.public_access_cidrs
  }

  access_config {
    authentication_mode                         = var.eks.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.eks.bootstrap_cluster_creator_admin_permissions
  }

  enabled_cluster_log_types = var.eks.enabled_cluster_log_types

  depends_on = [
    aws_iam_role_policy_attachment.cluster_eks_cluster_policy,
    aws_iam_role_policy_attachment.cluster_eks_vpc_resource_controller,
    aws_cloudwatch_log_group.eks_cluster,
  ]
}
