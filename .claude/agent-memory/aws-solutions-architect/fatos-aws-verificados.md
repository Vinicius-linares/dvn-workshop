---
name: fatos-aws-verificados
description: Fatos AWS/Terraform verificados via MCP que se repetem em ADRs de rede
metadata:
  type: reference
---

Fatos confirmados via MCP AWS/Terraform (2026-07-25), reutilizáveis:

- **Subnet reside inteiramente em UMA AZ** e não pode abranger zonas (VPC User Guide / VPC FAQ). Para HA, distribuir subnets em AZs distintas.
- **NAT Gateway**: HA confinada a uma única AZ. Recomendação AWS: 1 NAT GW por AZ para evitar SPOF e cobrança de tráfego inter-AZ. Single NAT GW = ponto único de falha + custo de dados cross-AZ quando subnets privadas estão em outra AZ.
- **Provider aws 6.56.0** (última). Recurso `aws_nat_gateway` no 6.x suporta `availability_mode` = `zonal` (default) ou `regional` (NAT gateway regional multi-AZ gerenciado, auto ou manual mode). Isso é alternativa de HA relevante a citar.
- `aws_subnet`: args-chave `vpc_id` (req), `cidr_block`, `availability_zone`, `map_public_ip_on_launch` (default false).
- `aws_nat_gateway` zonal público: `allocation_id` (EIP), `subnet_id`, recomenda-se `depends_on` no IGW.
- Route tables: `aws_route_table`, `aws_route_table_association`. IGW: `aws_internet_gateway`. EIP: `aws_eip` (arg `domain = "vpc"`).

**Why:** Evita reconsultar MCP e sustenta o trade-off de custo vs HA do NAT GW único.
**How to apply:** Citar nos ADRs de rede. Ver [[infra-estado-atual]].
