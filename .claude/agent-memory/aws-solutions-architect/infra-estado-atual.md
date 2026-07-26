---
name: infra-estado-atual
description: Estado atual da infraestrutura do projeto dvn-workshop-julho (VPC, região, provider, state backend)
metadata:
  type: project
---

Estado da infraestrutura em 2026-07-26 (repo dvn-workshop-julho):

- **Infra organizada em STACKS numeradas** em `dvn-workshop-terraform/`: `00-remote-backend-stack`, `01-networking-stack`. Convenção `NN-<nome>-stack`.
- **Conta AWS = `654654554686`**, região `us-east-1` (deduzido do nome do bucket de state).
- Provider `hashicorp/aws ~> 6.0`, lock `6.56.0`. Terraform `~> 1.10`. Provider usa `region = var.region` e `default_tags = var.default_tags` ({Environment=production, Project=dvn-workshop-julho}).
- **Backend remoto S3 ATIVO**: bucket `dvn-bigode-tfstate-654654554686-us-east-1` (ADR-0002, Aprovado). Key por stack, `use_lockfile = true`, `encrypt = true`.
- **`01-networking-stack` JÁ MIGRADA para o S3** (seu versions.tf tem `backend "s3"` key `01-networking-stack/terraform.tfstate`). Isto ATUALIZA o ADR-0002 que a descrevia como state local. VPC `10.0.0.0/24`, 2 subnets públicas + 2 privadas em us-east-1a/1b.
- **ADR-0003** (Não aprovado, 2026-07-26) propõe stack `02-eks-cluster-stack`: cluster EKS K8s 1.36 via módulo terraform-aws-modules/eks ~> 21.0, node group ON_DEMAND t3.medium desired 2/min 2/max 4, authentication_mode API_AND_CONFIG_MAP, IRSA, logging 5 tipos, acesso admin do criador via enable_cluster_creator_admin_permissions.
- Apps em `dvn-workshop-apps/` (frontend `youtube-live-app`, backend `YoutubeLiveApp`) — app de YouTube Live.

**Why:** Base para qualquer ADR de rede/infra deste projeto.
**How to apply:** Nova infra vai em stack numerada própria. O state local é risco real (11 recursos na 01). Ver [[convencoes-projeto]], [[fatos-aws-verificados]] e [[fatos-terraform-backend-s3]].
