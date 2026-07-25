---
name: conventions-terraform-naming
description: Convenções de nomenclatura e modelagem confirmadas para este projeto — extrato operacional da rule terraform-naming.md.
metadata:
  type: project
---

Confirmado da rule `.claude/rules/terraform-naming.md` e aplicado em ADR-0001:

**Nomes de arquivos:** `<dominio>.<componente>.tf` com `-` (dash) dentro dos segmentos. Ex: `vpc.public-route-table.tf`. Arquivos convencionais: `variables.tf`, `outputs.tf`, `versions.tf`, `providers.tf`.

**Nomes internos Terraform:** `_` (underscore), sem repetir o tipo no nome do bloco. `this` quando recurso único do tipo. Ex: `resource "aws_vpc" "this"`, NÃO `resource "aws_vpc" "aws_vpc"`.

**Modelagem de variables (Seção 6 — CRÍTICO):**
- Uma variável `vpc` do tipo `object({name, cidr, public_subnets: list(object({name, cidr, availability_zone})), private_subnets: list(...)})`.
- NUNCA variáveis isoladas por subnet (`vpc_cidr_block`, `public_subnet_cidr_a`, etc.).
- Valores concretos em `terraform.tfvars`, nunca inline nos resources.
- Iterar com `for_each = { for s in var.vpc.public_subnets : s.name => s }`.

**Outputs:** padrão `{name}_{type}_{attribute}`. Ex: `vpc_id`, `nat_gateway_id`, `internet_gateway_id`. NÃO `vpc_vpc_id`, NÃO `internet_gateway_internet_gateway_id`.

**Tags:** prefixo `dvn-bigode-` na tag `Name`. Tag `adr=ADR-NNNN` e `project=dvn-workshop-julho` via `default_tags` no provider (não repetir em cada recurso).

**Ordem de argumentos:** `for_each`/`count` primeiro, `tags` último (antes de `depends_on`/`lifecycle`).
