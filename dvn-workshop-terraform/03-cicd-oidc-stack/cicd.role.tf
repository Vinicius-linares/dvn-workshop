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
