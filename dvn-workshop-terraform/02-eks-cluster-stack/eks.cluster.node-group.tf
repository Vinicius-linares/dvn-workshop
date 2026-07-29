resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = var.eks.node_group.name
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = local.private_subnet_ids

  capacity_type  = var.eks.node_group.capacity_type
  instance_types = var.eks.node_group.instance_types

  scaling_config {
    desired_size = var.eks.node_group.desired_size
    min_size     = var.eks.node_group.min_size
    max_size     = var.eks.node_group.max_size
  }

  update_config {
    max_unavailable = var.eks.node_group.max_unavailable
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_eks_worker_node_policy,
    aws_iam_role_policy_attachment.node_eks_cni_policy,
    aws_iam_role_policy_attachment.node_ec2_container_registry_read_only,
  ]
}
