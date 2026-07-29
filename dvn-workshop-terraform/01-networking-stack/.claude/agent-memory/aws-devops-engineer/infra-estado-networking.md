---
name: infra-estado-networking
description: Estado atual da 01-networking-stack — recursos aplicados, backend e localização de state
metadata:
  type: project
---

Stack `01-networking-stack` (ADR-0001, aprovado Kenerry Serain, 2026-07-25) está aplicada e com backend **remoto S3** desde 2026-07-25.

**Recursos aplicados (14):**
- `aws_vpc.this` — `vpc-091e685cb6e93c7e3`, CIDR `10.0.0.0/24`
- `aws_subnet.public` × 2 — `dvn-bigode-subnet-public-a/b`, `us-east-1a/b`
- `aws_subnet.private` × 2 — `dvn-bigode-subnet-private-a/b`, `us-east-1a/b`
- `aws_internet_gateway.this` — `igw-0fed6dcacb76ad14c`
- `aws_eip.nat` — `eipalloc-0e1611a839b086876`
- `aws_nat_gateway.this` — `nat-057f4055152e35d10`
- `aws_route_table.public` — `rtb-0d86ec7123e474eb7`
- `aws_route_table.private` — `rtb-0c6ff516f115d8d32`
- `aws_route_table_association.public` × 2
- `aws_route_table_association.private` × 2

**Backend:** S3 — `dvn-bigode-tfstate-654654554686-us-east-1`, key `01-networking-stack/terraform.tfstate`, `use_lockfile = true`.

**Why:** Migração de state local para remoto executada como parte do ADR-0002 (autorizada explicitamente pelo usuário além do escopo textual do ADR).
**How to apply:** `terraform plan` pós-migração confirmou "No changes" — todos os 14 recursos preservados. Não há state local ativo; o `terraform.tfstate` local é apenas backup.
