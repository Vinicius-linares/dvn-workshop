data "aws_iam_policy_document" "ecr_push" {
  # ecr:GetAuthorizationToken does not support resource-level scoping by
  # repository ARN — it must be granted on Resource = "*".
  statement {
    sid       = "AllowECRLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push actions are scoped to the specific ECR repository ARNs obtained
  # from the 02-eks-cluster-stack remote state output. No ARN is hard-coded.
  #
  # BatchGetImage + GetDownloadUrlForLayer são de LEITURA, mas o docker buildx/
  # BuildKit as exige durante o push: antes de enviar, ele faz um HEAD no manifest
  # (e checa layers existentes) para pular uploads redundantes. Sem elas, o push
  # falha com 403 Forbidden no HEAD do manifest, mesmo com as ações de upload.
  statement {
    sid    = "AllowECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = local.ecr_repository_arns
  }
}

resource "aws_iam_policy" "ecr_push" {
  name        = "${var.github_oidc.role_name}-ecr-push"
  description = "Minimum permissions for GitHub Actions to log in and push images to the dvn-workshop ECR repositories."
  policy      = data.aws_iam_policy_document.ecr_push.json
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_push.arn
}
