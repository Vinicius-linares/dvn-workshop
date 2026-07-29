---
name: fatos-terraform-backend-s3
description: Fatos verificados via MCP sobre backend remoto Terraform em S3 (locking, versioning, encryption, public access block)
metadata:
  type: reference
---

Fatos confirmados via MCP (AWS docs + Terraform provider aws 6.56.0) em 2026-07-25, reutilizáveis em ADRs de backend/state:

- **S3 native state locking** via `use_lockfile = true` no bloco `backend "s3"`: disponível **desde Terraform 1.10.0**, é o método **RECOMENDADO** pela AWS (Prescriptive Guidance "Backend best practices"). **DynamoDB locking está DEPRECADO** e será removido em versões futuras do Terraform. Não precisa mais de tabela DynamoDB.
- Versionamento é recurso SEPARADO do bucket no provider 6.x: `aws_s3_bucket_versioning` com bloco `versioning_configuration { status = "Enabled" }`. Status `Disabled` só serve p/ criar/importar bucket unversioned; mudar Enabled→Disabled dá ERRO (S3 API não volta a unversioned; use `Suspended`). Após habilitar versioning pela 1a vez, AWS recomenda esperar ~15 min antes de escritas.
- Criptografia SSE server-side: recurso separado `aws_s3_bucket_server_side_encryption_configuration`. SSE-S3 = `sse_algorithm = "AES256"` (sem custo KMS). SSE-KMS = controle/auditoria de chave, mas custo + key policy + kms:Decrypt p/ quem roda terraform.
- Bloqueio público: `aws_s3_bucket_public_access_block` (4 flags de bloqueio). Política: `aws_s3_bucket_policy` (ex.: negar `aws:SecureTransport = false`).
- Nome de bucket S3 é GLOBALMENTE único. Estratégia: prefixo projeto + account id (`data aws_caller_identity`, não hardcoded) + região, derivado em `locals`.
- **Chicken-and-egg**: stack que cria o backend nasce com state LOCAL; após criar o bucket, adiciona `backend "s3"` e roda `terraform init -migrate-state`. Cada stack usa `key` própria no mesmo bucket.
- Proteger bucket de state com `lifecycle { prevent_destroy = true }` (é o state de todas as stacks).

**Why:** Evita reconsultar MCP em ADRs de backend/state remoto.
**How to apply:** Citar em ADRs de state backend. Ver [[infra-estado-atual]] e ADR-0002.
