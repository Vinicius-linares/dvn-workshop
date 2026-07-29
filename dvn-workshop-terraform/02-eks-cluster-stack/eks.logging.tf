resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.eks.name}/cluster"
  retention_in_days = var.eks.log_retention_in_days
}
