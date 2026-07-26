---
name: infra-estado-oidc-cicd
description: Stack 03-cicd-oidc-stack aplicada — OIDC provider GitHub + IAM role para push ECR via GitHub Actions.
metadata:
  type: project
---

Stack `03-cicd-oidc-stack` aplicada em 2026-07-26 (ADR-0004, Kenerry Serain).

**OIDC Provider:**
- ARN: `arn:aws:iam::654654554686:oidc-provider/token.actions.githubusercontent.com`
- `client_id_list = ["sts.amazonaws.com"]`, sem thumbprint (B1 — AWS valida via CA para GitHub)
- Verificado antes do apply: não havia provider GitHub na conta; apenas 6 providers EKS/IRSA

**IAM Role:**
- Nome: `dvn-bigode-github-actions-ecr`
- ARN: `arn:aws:iam::654654554686:role/dvn-bigode-github-actions-ecr`
- Trust: `sts:AssumeRoleWithWebIdentity`, principal Federated = OIDC provider acima
- Conditions: `:aud = sts.amazonaws.com` (StringEquals) e `:sub = repo:kenerry-serain/dvn-workshop-julho:*` (StringLike)

**IAM Policy (least privilege):**
- Nome: `dvn-bigode-github-actions-ecr-ecr-push`
- Statement 1: `ecr:GetAuthorizationToken` em `Resource = "*"` (obrigatório)
- Statement 2: `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage` em ARNs dos repos ECR (do remote state da 02)
- ARNs dos repos: `arn:aws:ecr:us-east-1:654654554686:repository/dvn-workshop/production/backend` e `.../frontend`

**State S3 key:** `03-cicd-oidc-stack/terraform.tfstate`
**Tag de rastreabilidade:** `adr = "ADR-0004"` via default_tags

**Uso nos workflows (ADR-0006):**
- Armazenar o ARN da role em `vars.AWS_GHA_ROLE_ARN` no repositório GitHub
- Use `aws-actions/configure-aws-credentials` com `role-to-assume: ${{ vars.AWS_GHA_ROLE_ARN }}`

**Why:** Eliminar credenciais de longa duração no CI; least privilege escopado por ARN de repo.
**How to apply:** Output `github_actions_role_arn` = ARN a configurar como variável no repo GitHub. Ver [[infra-remote-backend]].
