---
name: infra-estado-atual
description: Estado atual da infraestrutura do projeto dvn-workshop-julho (VPC, região, provider, state backend)
metadata:
  type: project
---

Estado da infraestrutura em 2026-07-25 (repo dvn-workshop-julho):

- **Infra agora é organizada em STACKS numeradas** dentro de `dvn-workshop-terraform/`: `01-networking-stack/` já existe e foi APLICADA. Convenção `NN-<nome>-stack`.
- Provider `hashicorp/aws ~> 6.0`, lock `6.56.0` (última). Terraform constraint `~> 1.10` no `versions.tf` da stack.
- Provider da `01` agora usa `region = var.region` e `default_tags = var.default_tags` (NÃO mais hardcoded us-east-1 como no começo do ADR-0001).
- **`01-networking-stack` está APLICADA**: `terraform.tfstate` tem **11 recursos** (serial 15), backend LOCAL (sem bloco backend). Corrige nota anterior de "tfstate vazio" — a rede está no ar com state local.
- **State backend ainda é LOCAL em todas as stacks**. Sem S3/DynamoDB até 2026-07-25.
- **ADR-0002** (status: Não aprovado, 2026-07-25) propõe stack `00-remote-backend-stack` com bucket S3 de backend remoto (versionamento + SSE-S3 + public access block + bucket policy + native lockfile `use_lockfile`). NÃO migra a `01` (fica p/ depois).
- Apps em `dvn-workshop-apps/` (frontend `youtube-live-app`, backend `YoutubeLiveApp`) — app de YouTube Live.

**Why:** Base para qualquer ADR de rede/infra deste projeto.
**How to apply:** Nova infra vai em stack numerada própria. O state local é risco real (11 recursos na 01). Ver [[convencoes-projeto]], [[fatos-aws-verificados]] e [[fatos-terraform-backend-s3]].
