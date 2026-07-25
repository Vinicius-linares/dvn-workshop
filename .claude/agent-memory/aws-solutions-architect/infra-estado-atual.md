---
name: infra-estado-atual
description: Estado atual da infraestrutura do projeto dvn-workshop-julho (VPC, região, provider, state backend)
metadata:
  type: project
---

Estado da infraestrutura em 2026-07-25 (repo dvn-workshop-julho):

- Terraform em `dvn-workshop-terraform/`. Provider `hashicorp/aws ~> 6.0`, lock em `6.56.0` (que é a última versão). Terraform CLI 1.10.3.
- Provider configurado para região `us-east-1` (hardcoded no provider block, não é variável).
- Só existe uma `aws_vpc.this` declarada, com `cidr_block = var.vpc.cidr_block`. A variável `vpc` tem **default `10.0.0.0/16`** — divergente do CIDR /24 pedido nos ADRs de rede.
- `outputs.tf` expõe apenas `vpc_id`.
- **State backend é LOCAL** (`terraform.tfstate` no diretório). Sem S3/DynamoDB. tfstate atual está vazio (0 recursos aplicados) — a VPC ainda não foi aplicada.
- Apps em `dvn-workshop-apps/` (frontend `youtube-live-app`, backend `YoutubeLiveApp`) — app de YouTube Live.

**Why:** Base para qualquer ADR de rede/infra deste projeto.
**How to apply:** Ao propor rede, apontar a divergência do CIDR default (/16 no código vs /24 pedido) e o state local como risco. Ver [[convencoes-projeto]] e [[fatos-aws-verificados]].
