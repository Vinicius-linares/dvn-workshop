---
name: convencoes-projeto
description: Convenções de naming, ADR e tagging observadas no projeto dvn-workshop-julho
metadata:
  type: project
---

Convenções do repo dvn-workshop-julho (não há CLAUDE.md nem MEMORY.md na raiz que as formalizem — foram inferidas do código):

- **Naming**: recursos usam prefixo `dvn-bigode-` na tag `Name` (ex.: VPC `dvn-bigode-vpc`).
- **ADRs**: não existia diretório `docs/` nem ADR anterior. O primeiro ADR criado foi `ADR-0001`. Numeração sequencial, kebab-case no slug: `docs/ADR-NNNN-<slug>.md`.
- Todo recurso AWS de um ADR deve carregar a tag `adr=ADR-NNNN`.
- Agentes definidos em `.claude/agents/`: `aws-solutions-architect` (planeja ADR) e `aws-devops-engineer` (implementa ADR aprovado). Fronteira: arquiteto decide o quê/porquê; engineer decide como escrever.
- **Rule de nomenclatura Terraform**: existe `.claude/rules/terraform-naming.md` (baseada em terraform-best-practices.com/naming). Define nomes internos com `_` (não repetir tipo do recurso, singular, `count`/`for_each` primeiro, `tags` último), outputs `{name}_{type}_{attribute}`, e — Seção 5 — layout de arquivos no padrão `<dominio>.<componente>.tf` (kebab-case com `-` nos nomes de ARQUIVO; um recurso/grupo coeso por arquivo; `vpc.tf` = recurso central). ADRs de rede devem referenciar essa rule na seção de layout. Ex. aplicado no ADR-0001: `vpc.tf`, `vpc.public-subnets.tf`, `vpc.private-subnets.tf`, `vpc.internet-gateway.tf`, `vpc.nat-gateway.tf` (NAT+EIP juntos), `vpc.public-route-table.tf`, `vpc.private-route-table.tf` (route table + associações juntas).

**Why:** Manter consistência entre ADRs e com o código existente.
**How to apply:** Numerar novos ADRs a partir do maior existente +1; aplicar tag Name com prefixo dvn-bigode- e tag adr=. Ver [[infra-estado-atual]].
