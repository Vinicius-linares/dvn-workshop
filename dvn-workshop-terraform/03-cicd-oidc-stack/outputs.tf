output "github_actions_role_arn" {
  description = "ARN of the IAM role assumable by GitHub Actions via OIDC. Use this as the role-to-assume in the configure-aws-credentials action."
  value       = aws_iam_role.github_actions.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the IAM OIDC identity provider for token.actions.githubusercontent.com."
  value       = aws_iam_openid_connect_provider.github.arn
}
