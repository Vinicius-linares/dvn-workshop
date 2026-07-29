---
name: infra-remote-backend
description: Estado atual do backend remoto Terraform — bucket S3, keys por stack, e configuração de locking nativo
metadata:
  type: project
---

Bucket S3 de state remoto criado e ativo pelo ADR-0002 (aprovado Kenerry Serain, 2026-07-25).

**Bucket:** `dvn-bigode-tfstate-654654554686-us-east-1`
**ARN:** `arn:aws:s3:::dvn-bigode-tfstate-654654554686-us-east-1`
**Região:** `us-east-1`
**Account ID:** `654654554686`

Configurações ativas:
- Versionamento: `Enabled`
- Criptografia: SSE-S3 (AES256)
- Public access block: 4 flags ativas
- Bucket policy: DenyInsecureTransport
- `prevent_destroy = true` no resource `aws_s3_bucket.state`

Keys por stack (no mesmo bucket):
- `00-remote-backend-stack/terraform.tfstate` — stack que provisiona o próprio bucket
- `01-networking-stack/terraform.tfstate` — stack de rede (ADR-0001)

State locking: `use_lockfile = true` (nativo S3, sem DynamoDB), Terraform >= 1.10.

**Why:** Resolver dívida de state local da infra; versionamento + lock previnem corrupção.
**How to apply:** Ao adicionar novas stacks, use key distinta `<nome-da-stack>/terraform.tfstate` no mesmo bucket. Nunca destruir este bucket sem remover `prevent_destroy` primeiro e garantir que nenhuma stack depende dele.
