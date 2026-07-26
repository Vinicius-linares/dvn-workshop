data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    sid     = "AllowGitHubActionsAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = var.github_oidc.audiences
    }

    # Restringe ao repositório usando o claim `repository` (owner/repo), que é
    # ESTÁVEL e não é afetado pela customização de OIDC claims do GitHub — ao
    # contrário do `sub`, que nesta org vem com os IDs numéricos imutáveis
    # embutidos (ex.: repo:owner@38140596/repo@1308958551:ref:...), quebrando um
    # StringLike simples sobre `sub`.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository"
      values   = [var.github_oidc.repository_claim]
    }

    # Defesa em profundidade: limita ao ref/branch via `sub`, tolerando os
    # segmentos @<id> que o GitHub injeta antes de `:ref:...`.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [var.github_oidc.subject_claim]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = var.github_oidc.role_name
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Name = var.github_oidc.role_name
  }
}
