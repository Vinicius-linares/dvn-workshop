---
name: project-infra-state
description: Estado atual da infraestrutura do dvn-workshop-julho — módulos, backends, providers e ADRs implementados.
metadata:
  type: project
---

ADR-0001 implementado em `dvn-workshop-terraform/01-networking-stack/` (arquivos escritos, fmt e validate limpos em 2026-07-25). Apply pendente de confirmação humana.

**Provider:** hashicorp/aws ~> 6.0, lock 6.56.0. Terraform CLI ~> 1.10. Região: us-east-1. Backend: local (terraform.tfstate no diretório do módulo).

**Recursos declarados (ainda não aplicados):**
- `aws_vpc.this` — 10.0.0.0/24, dns_support + dns_hostnames habilitados
- `aws_subnet.public` (for_each) — dvn-bigode-subnet-public-a (10.0.0.0/26, us-east-1a), dvn-bigode-subnet-public-b (10.0.0.64/26, us-east-1b)
- `aws_subnet.private` (for_each) — dvn-bigode-subnet-private-a (10.0.0.128/26, us-east-1a), dvn-bigode-subnet-private-b (10.0.0.192/26, us-east-1b)
- `aws_internet_gateway.this` — dvn-bigode-igw
- `aws_eip.nat` — dvn-bigode-eip-nat, domain=vpc
- `aws_nat_gateway.this` — dvn-bigode-nat, zonal, subnet pública da AZ-a
- `aws_route_table.public` + 2x `aws_route_table_association.public` — 0.0.0.0/0 → IGW
- `aws_route_table.private` + 2x `aws_route_table_association.private` — 0.0.0.0/0 → NAT GW

**Tag de rastreabilidade:** `adr = "ADR-0001"` aplicada via default_tags no provider (providers.tf).
**Tag de projeto:** `project = "dvn-workshop-julho"` também via default_tags.

**Why:** ADR-0001 aprovado por Kenerry Serain em 2026-07-25.
**How to apply:** Verificar estado antes de recomendar recursos já existentes; confirmar apply com o usuário antes de executar.
