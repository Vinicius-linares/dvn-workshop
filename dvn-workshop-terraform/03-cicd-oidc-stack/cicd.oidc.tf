# IAM OIDC identity provider for GitHub Actions.
# Per AWS documentation and ADR-0004 (decision B1): for GitHub, AWS validates
# the JWKS endpoint against its own CA library, so thumbprint_list is omitted.
resource "aws_iam_openid_connect_provider" "github" {
  url            = var.github_oidc.provider_url
  client_id_list = var.github_oidc.audiences
}
