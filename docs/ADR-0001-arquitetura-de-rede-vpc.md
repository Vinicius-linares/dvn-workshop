---
id: ADR-0001
titulo: Arquitetura de rede base na AWS — VPC 10.0.0.0/24 com subnets públicas/privadas e NAT Gateway único
status: Aprovado
data: 2026-07-25
substitui: N/A
aprovado_por: Kenerry Serain
aprovado_em: 2026-07-25
---

# ADR-0001 — Arquitetura de rede base na AWS

## 1. Contexto

O projeto `dvn-workshop-julho` hospeda uma aplicação de YouTube Live (frontend `youtube-live-app` e backend `YoutubeLiveApp`, em `dvn-workshop-apps/`) e precisa de uma fundação de rede na AWS para receber as cargas de trabalho. Hoje, o estado da infraestrutura (código em `dvn-workshop-terraform/`) é o seguinte:

- Provider `hashicorp/aws` com constraint `~> 6.0`, lock em `6.56.0` (última versão disponível, confirmada via MCP Terraform). Terraform CLI `1.10.3`.
- Provider fixado na região **`us-east-1`** (hardcoded no bloco `provider`, não parametrizado).
- Existe apenas um recurso `aws_vpc.this` declarado, com `cidr_block = var.vpc.cidr_block`, cuja variável tem **default `10.0.0.0/16`**. O `terraform.tfstate` está **vazio** — nenhum recurso foi aplicado ainda.
- **State backend é local** (`terraform.tfstate` no diretório do módulo). Não há S3 nem lock via DynamoDB/S3 lockfile.
- Convenção de naming observada no código: tag `Name` com prefixo `dvn-bigode-` (ex.: `dvn-bigode-vpc`).
- **Não existem `CLAUDE.md`, `MEMORY.md` nem diretório `docs/`** na raiz. Este é o **primeiro ADR** do projeto (ADR-0001) e não substitui nenhum outro.

Este ADR define a topologia de rede base a ser implementada pelo agente DevOps Engineer.

### Requisitos definidos pelo usuário
- CIDR da VPC: **`10.0.0.0/24`** (256 endereços).
- **4 subnets**, cada uma **/26** (64 endereços, ~59 utilizáveis por subnet após reserva AWS de 5 IPs):
  - Públicas: `10.0.0.0/26` e `10.0.0.64/26`
  - Privadas: `10.0.0.128/26` e `10.0.0.192/26`
- **Um único NAT Gateway** (single NAT gateway) para egresso das subnets privadas.

### Conflito detectado (a resolver antes da implementação)
O código atual define a VPC com CIDR default `10.0.0.0/16`, enquanto este ADR especifica `10.0.0.0/24`. São incompatíveis. A implementação **deve** alterar o `default`/valor da variável `vpc.cidr_block` para `10.0.0.0/24` (ou passá-lo explicitamente). Como o state está vazio, não há recurso VPC aplicado a destruir — a mudança é apenas de configuração antes do primeiro `apply`. Ver Premissa 1.

## 2. Drivers da decisão

Em ordem de prioridade para este contexto de workshop:

1. **Aderência à especificação do usuário** — o desenho de CIDR/subnets/NAT é um requisito fechado.
2. **Custo** — contexto de workshop; minimizar gasto recorrente. NAT Gateway é o item de maior custo fixo da topologia.
3. **Simplicidade operacional** — desenho fácil de entender, aplicar e destruir ao fim do workshop.
4. **Segurança de base** — separação pública/privada, egresso controlado, least privilege nas rotas.
5. **Disponibilidade** — desejável distribuir em múltiplas AZs, porém subordinada aos drivers 2 e 3 neste contexto (o próprio usuário optou por NAT único).

## 3. Opções consideradas

Todas as opções compartilham: 1 VPC `10.0.0.0/24`, IGW único, 4 subnets /26 conforme especificado, subnets públicas com rota default para o IGW. A diferença central está na **estratégia de egresso das subnets privadas (NAT)** e na **distribuição em AZs**.

### Opção A — NAT Gateway único, subnets em 2 AZs (escolhida)
- 1 NAT Gateway (zonal) em **uma** subnet pública, com 1 Elastic IP.
- Subnets distribuídas em **2 AZs** (`us-east-1a` e `us-east-1b`): 1 pública + 1 privada por AZ.
- 1 route table pública (rota `0.0.0.0/0` → IGW) associada às 2 públicas; 1 route table privada (rota `0.0.0.0/0` → NAT GW) associada às 2 privadas.

Trade-offs:
- **Custo**: menor — apenas 1 NAT GW (custo/hora + custo/GB processado) e 1 EIP. Verificar valores atuais na calculadora AWS `[NÃO VERIFICADO]`.
- **Disponibilidade**: NAT é **ponto único de falha**; se a AZ do NAT cair, a subnet privada da outra AZ perde egresso à internet. AWS confirma (via MCP) que a HA do NAT GW é confinada a uma única AZ.
- **Custo de dados cross-AZ**: a subnet privada que **não** está na AZ do NAT paga transferência inter-AZ ao sair pela internet. Confirmado como recomendação AWS (1 NAT por AZ evita isso) via MCP.
- **Operação**: simples — atende exatamente ao pedido.

### Opção B — NAT Gateway por AZ (1 por AZ, alta disponibilidade)
- 2 NAT Gateways (1 por AZ), 2 EIPs, 2 route tables privadas (cada privada roteia para o NAT da própria AZ).

Trade-offs:
- **Disponibilidade**: melhor — falha de uma AZ não afeta o egresso da outra. Recomendação AWS para produção (confirmada via MCP).
- **Custo**: ~2x o custo de NAT GW + 1 EIP adicional. Elimina transferência inter-AZ para egresso.
- **Contradiz o requisito explícito** do usuário (single NAT gateway). Descartada por esse motivo, mas documentada como caminho de evolução para produção.

### Opção C — NAT Gateway regional (availability_mode = "regional")
- Recurso `aws_nat_gateway` com `availability_mode = "regional"` (feature do provider 6.x, confirmada via MCP), gerenciado pela AWS com cobertura multi-AZ automática (auto mode) ou manual.

Trade-offs:
- **Disponibilidade**: multi-AZ gerenciado, sem precisar declarar um NAT por AZ manualmente.
- **Custo/comportamento**: modelo de cobrança e disponibilidade regional na região-alvo `[NÃO VERIFICADO]` — precisa de confirmação de custo e de disponibilidade em `us-east-1` antes de adotar.
- **Contradiz "single NAT gateway"** no sentido literal (é um NAT regional, não zonal único) e adiciona conceito novo ao workshop. Descartada por complexidade/novidade e por divergir do pedido, mas registrada como alternativa moderna à Opção B.

## 4. Decisão

Adotar a **Opção A — NAT Gateway único, com subnets distribuídas em 2 AZs**.

Justificativa frente aos drivers:
- Atende **exatamente** ao requisito do usuário (driver 1): VPC `/24`, 4 subnets `/26` nos CIDRs especificados, **um único NAT Gateway**.
- Minimiza **custo** (driver 2): um só NAT GW e um só EIP.
- Mantém **simplicidade** (driver 3): duas route tables (uma pública, uma privada), fácil de aplicar e destruir.
- Preserva **segurança de base** (driver 4): separação pública/privada e egresso das privadas via NAT (sem IP público, sem entrada não solicitada).
- Sobre **disponibilidade** (driver 5): distribuímos as subnets em 2 AZs mesmo com NAT único, porque isso não adiciona custo e melhora a resiliência das cargas *stateful* nas subnets; o egresso, porém, continua dependente da AZ do NAT — dívida técnica aceita e documentada.

O mapeamento AZ das subnets **não** foi especificado pelo usuário. Decisão de arquitetura: alocar em 2 AZs distintas da região `us-east-1` para permitir cargas multi-AZ. A escolha concreta das AZs deve usar o data source de AZs disponíveis (não fixar letras no código) — ver Boas Práticas. O NAT GW será colocado na subnet pública da **primeira** AZ.

## 5. Consequências

Positivas:
- Custo recorrente mínimo de NAT (1 unidade).
- Fundação de rede clara, com separação pública/privada e egresso controlado.
- Subnets em 2 AZs habilitam futuras cargas multi-AZ sem redesenhar o CIDR.

Negativas / dívida técnica aceita:
- **SPOF de egresso**: falha na AZ do NAT deixa a subnet privada da outra AZ sem saída para a internet. Aceito para contexto de workshop.
- **Custo de transferência inter-AZ**: tráfego de egresso da subnet privada que não está na AZ do NAT cruza AZ e é tarifado. Aceito.
- **Espaço de endereçamento pequeno**: `/24` com 4 subnets `/26` consome **todo** o bloco da VPC — não sobra espaço para novas subnets sem adicionar um CIDR secundário à VPC. Aceito; registrado como risco.
- **Sem HA de NAT** — evoluir para Opção B/C exige novo ADR.

## 6. Plano de implementação

Passos atômicos, ordenados por dependência. Cada passo tem critério de conclusão verificável. O DevOps Engineer decide o "como escrever" (nomes de locals, uso de `count`/`for_each`, módulos internos). **A organização dos recursos em arquivos deve seguir o layout da Seção 7** (padrão `<dominio>.<componente>.tf` da rule `.claude/rules/terraform-naming.md`); cada passo abaixo indica o arquivo-alvo correspondente.

0. **Reorganizar o módulo para o layout de arquivos da Seção 7.**
   Se o código atual concentra provider + VPC em `main.tf`, dividir nos arquivos do padrão `<dominio>.<componente>.tf` (extrair `providers.tf` e `versions.tf`, criar `vpc.tf`, etc.). É reorganização física de arquivos, sem alterar os nomes dos blocos, portanto sem impacto no state.
   *Conclusão:* a árvore de arquivos do módulo corresponde à Seção 7; `terraform validate` limpo e `terraform plan` sem mudanças decorrentes apenas da reorganização.

1. **Ajustar o CIDR da VPC para `10.0.0.0/24`.** (arquivo: `vpc.tf` / `variables.tf`)
   Alterar o valor efetivo de `var.vpc.cidr_block` (default ou tfvars) de `10.0.0.0/16` para `10.0.0.0/24`, mantendo a VPC `aws_vpc.this` existente.
   *Conclusão:* `terraform plan` mostra a VPC com `cidr_block = "10.0.0.0/24"` e nenhuma recriação inesperada (state está vazio).

2. **Selecionar 2 AZs da região via data source.** (arquivo: `vpc.tf` ou onde as subnets são declaradas)
   Usar `data "aws_availability_zones"` (estado `available`) para obter dinamicamente as 2 primeiras AZs de `us-east-1`, sem fixar letras no código.
   *Conclusão:* `plan` referencia 2 AZs distintas resolvidas pelo data source.

3. **Criar as 2 subnets públicas** (`10.0.0.0/26`, `10.0.0.64/26`), uma em cada AZ, com `map_public_ip_on_launch = true`. (arquivo: `vpc.public-subnets.tf`)
   *Conclusão:* `plan` cria 2 `aws_subnet` públicas nos CIDRs exatos, em AZs distintas.

4. **Criar as 2 subnets privadas** (`10.0.0.128/26`, `10.0.0.192/26`), uma em cada AZ, sem IP público automático. (arquivo: `vpc.private-subnets.tf`)
   *Conclusão:* `plan` cria 2 `aws_subnet` privadas nos CIDRs exatos, alinhadas às mesmas AZs das públicas.

5. **Criar o Internet Gateway** e anexá-lo à VPC. (arquivo: `vpc.internet-gateway.tf`)
   *Conclusão:* `plan` cria 1 `aws_internet_gateway` associado a `aws_vpc.this`.

6. **Alocar 1 Elastic IP** para o NAT Gateway (`domain = "vpc"`). (arquivo: `vpc.nat-gateway.tf`)
   *Conclusão:* `plan` cria 1 `aws_eip` para uso do NAT.

7. **Criar 1 NAT Gateway (zonal, público)** na subnet pública da primeira AZ, usando o EIP do passo 6, com `depends_on` no IGW. (arquivo: `vpc.nat-gateway.tf` — mesmo arquivo do EIP, grupo coeso)
   *Conclusão:* `plan` cria 1 `aws_nat_gateway` com `allocation_id` do EIP e `subnet_id` da pública da AZ primária.

8. **Criar a route table pública** com rota `0.0.0.0/0` → IGW e **associá-la às 2 subnets públicas**. (arquivo: `vpc.public-route-table.tf` — route table + associações no mesmo arquivo)
   *Conclusão:* `plan` cria 1 `aws_route_table` pública, 1 rota default para o IGW e 2 `aws_route_table_association` (uma por subnet pública).

9. **Criar a route table privada** com rota `0.0.0.0/0` → NAT Gateway e **associá-la às 2 subnets privadas**. (arquivo: `vpc.private-route-table.tf` — route table + associações no mesmo arquivo)
   *Conclusão:* `plan` cria 1 `aws_route_table` privada, 1 rota default para o NAT GW e 2 `aws_route_table_association` (uma por subnet privada).

10. **Expor outputs** relevantes: `vpc_id` (já existente), IDs das subnets públicas/privadas, ID do NAT GW e do IGW. (arquivo: `outputs.tf`)
    *Conclusão:* `terraform output` lista os IDs após `apply`.

11. **Aplicar e validar** (ver seção 11).
    *Conclusão:* `apply` conclui sem erro; validações da seção 11 passam.

## 7. Layout de diretórios

A organização física dos arquivos `.tf` **deve** seguir a rule `.claude/rules/terraform-naming.md`, **Seção 5 (Layout de arquivos)**: um recurso (ou grupo coeso de recursos do mesmo propósito) por arquivo, no padrão `<dominio>.<componente>.tf`, com prefixo de domínio consistente (`vpc`) e sufixos descritivos em kebab-case. Isto substitui a abordagem anterior de concentrar tudo em `main.tf`/`network.tf`. Esta árvore é o **contrato de organização de arquivos** (obrigatório); o Engineer continua definindo os nomes internos do Terraform (locals, uso de `count`/`for_each`, etc.).

```
dvn-workshop-terraform/
├── vpc.tf                       # recurso central do domínio: a VPC (aws_vpc.this) — ajustar CIDR p/ /24
├── vpc.public-subnets.tf        # 2 subnets públicas (10.0.0.0/26, 10.0.0.64/26)
├── vpc.private-subnets.tf       # 2 subnets privadas (10.0.0.128/26, 10.0.0.192/26)
├── vpc.internet-gateway.tf      # Internet Gateway anexado à VPC
├── vpc.nat-gateway.tf           # NAT Gateway único (zonal) + Elastic IP
├── vpc.public-route-table.tf    # route table pública (0.0.0.0/0 → IGW) + associações às públicas
├── vpc.private-route-table.tf   # route table privada (0.0.0.0/0 → NAT GW) + associações às privadas
├── variables.tf                 # variável vpc (ajustar CIDR p/ /24); vars de subnets se parametrizado
├── outputs.tf                   # vpc_id + IDs de subnets, NAT GW e IGW
├── versions.tf                  # pin do Terraform e do provider (~> 6.0)
├── providers.tf                 # bloco provider (região, default_tags)
└── terraform.tfstate            # state LOCAL atual — ver risco de backend na seção 9
```

Observações:
- Os nomes de **arquivos** usam `-` (dash) dentro de cada segmento (ex.: `public-route-table`), conforme a exceção explícita da Seção 5 da rule; os **nomes internos do Terraform** (blocos `resource`/`data`) continuam com `_` (underscore) e sem repetir o tipo do recurso, conforme as Seções 1 e 2 da mesma rule.
- Se o módulo hoje concentra provider + VPC em `main.tf`, a migração para este layout é uma reorganização de arquivos sem impacto no state (os endereços dos recursos no state dependem do nome do bloco, não do nome do arquivo). Caso `versions.tf`/`providers.tf` ainda não existam separados, o Engineer pode extraí-los de `main.tf`.
- A associação route table ↔ subnet vive no mesmo arquivo da respectiva route table (grupo coeso), conforme o exemplo da rule.

## 8. Boas práticas aplicáveis

- **Tag obrigatória de rastreabilidade**: **todo recurso AWS criado a partir deste ADR deve carregar a tag `adr=ADR-0001`.** Recomenda-se aplicá-la centralmente via `default_tags` no provider (não repetir em cada recurso).
- **Layout e nomenclatura de arquivos/código**: seguir a rule `.claude/rules/terraform-naming.md`. Layout físico conforme Seção 5 (`<dominio>.<componente>.tf`, ver Seção 7 deste ADR); nomes internos do Terraform com `_`, sem repetir o tipo do recurso, substantivos no singular, `count`/`for_each` como primeiro argumento e `tags` como último (Seções 1–2 da rule); outputs no padrão `{name}_{type}_{attribute}` com `description` (Seções 3–4).
- **Tagging/naming**: manter o prefixo de projeto `dvn-bigode-` na tag `Name` (ex.: `dvn-bigode-subnet-public-a`), coerente com a VPC existente. Diferenciar público/privado e AZ no nome.
- **AZs dinâmicas**: usar `data "aws_availability_zones"` em vez de fixar `us-east-1a/b` no código — evita quebra se uma AZ não estiver disponível na conta.
- **Least privilege de rotas**: subnets privadas só com rota default para o NAT (sem rota para o IGW); subnets públicas com rota para o IGW. Não criar rotas amplas desnecessárias.
- **Idempotência**: CIDRs de subnet fixos e AZs resolvidas por índice estável do data source para evitar *drift* entre `plan`s.
- **State**: o backend atual é **local** — ver risco na seção 9. Para trabalho colaborativo/durável, migrar para backend remoto (ex.: S3 com lock) deve ser tratado em ADR próprio, não aqui.
- **Versionamento**: manter o pin do provider `~> 6.0` (lock `6.56.0`) já presente; não fazer upgrade de provider dentro deste ADR.
- **`depends_on` explícito** do NAT GW no IGW, conforme recomendação do provider, para ordenação correta de criação.

## 9. Riscos e mitigações

- **SPOF de egresso (NAT único)** — mitigação: aceito para workshop; evoluir para Opção B/C via novo ADR se virar produção.
- **Custo de transferência inter-AZ** para egresso da privada fora da AZ do NAT — mitigação: aceito; se relevante, colocar cargas de egresso intenso na AZ do NAT ou adotar Opção B.
- **Esgotamento do CIDR `/24`** — as 4 subnets `/26` consomem todo o bloco; não há espaço para novas subnets. Mitigação: se precisar crescer, adicionar CIDR secundário à VPC (`aws_vpc_ipv4_cidr_block_association`) em ADR futuro.
- **State local** — risco de perda/conflito do `terraform.tfstate` (sem versionamento remoto nem lock). Mitigação: tratar migração de backend em ADR dedicado antes de uso multiusuário.
- **Conflito de CIDR /16 → /24** — o default atual da variável diverge do ADR. Mitigação: passo 1 do plano corrige antes do primeiro `apply` (state vazio, sem recriação).
- **[NÃO VERIFICADO] Custo mensal do NAT Gateway e do EIP em `us-east-1`** — não confirmado via MCP nesta sessão; validar na calculadora de preços AWS antes de aprovar orçamento.
- **[NÃO VERIFICADO] Disponibilidade/custo do NAT Gateway "regional" (Opção C) em `us-east-1`** — feature confirmada no provider, mas comportamento/preço na região não verificados.
- **[NÃO VERIFICADO] Número de AZs disponíveis na conta** em `us-east-1` — assume-se ≥2; o data source do passo 2 confirma em tempo de `plan`.

## 10. Rollback

O egresso do passo 11 é um `apply` que cria recursos novos; como o state está vazio, o rollback global é um `terraform destroy` do módulo (ou reverter os arquivos e reaplicar). Por passo irreversível/ordenado:

- Passos 3–9 (subnets, IGW, EIP, NAT GW, route tables): reverter removendo os recursos do código e aplicando, ou `terraform destroy -target` nos recursos criados. Ordem de destruição inversa: associações → route tables → NAT GW → EIP → IGW → subnets.
- Passo 1 (CIDR): como a VPC ainda não foi aplicada (state vazio), reverter é apenas restaurar o valor anterior da variável. **Se a VPC já tiver sido aplicada com `/24`**, mudar o CIDR força recriação da VPC — nesse caso o rollback é destrutivo e deve ser tratado com cuidado (destruir dependências primeiro).
- O NAT Gateway leva alguns minutos para deletar (timeout default de destroy de 30m no provider) — aguardar conclusão antes de liberar o EIP.

## 11. Validação

O DevOps Engineer deve comprovar ao final:

1. `terraform validate` e `terraform fmt -check` limpos.
2. `terraform plan` **sem mudanças pendentes** após o `apply` (convergência/idempotência).
3. VPC com CIDR `10.0.0.0/24`; 4 subnets exatamente em `10.0.0.0/26`, `10.0.0.64/26`, `10.0.0.128/26`, `10.0.0.192/26`, distribuídas em 2 AZs (2 públicas + 2 privadas).
4. Route table pública com rota `0.0.0.0/0` → IGW associada às 2 públicas; route table privada com rota `0.0.0.0/0` → NAT GW associada às 2 privadas.
5. Exatamente **1** NAT Gateway e **1** EIP criados.
6. Todos os recursos com a tag `adr=ADR-0001` (verificável no console ou via `terraform state show`).
7. Teste funcional de egresso: um recurso em subnet privada (ex.: instância de teste) alcança a internet via NAT (ex.: `curl` a um endpoint público) e **não** é alcançável de entrada pela internet.
8. `terraform output` retorna os IDs esperados (VPC, subnets, NAT GW, IGW).

## 12. Premissas

Como o pedido foi para seguir sem rodada de perguntas, registro as premissas — cada uma é ponto de validação humana antes/na aprovação:

1. **CIDR da VPC deve mudar de `10.0.0.0/16` para `10.0.0.0/24`** no código antes do `apply`. Assume-se autorização para alterar o default/valor da variável `vpc.cidr_block`.
2. **Região `us-east-1`** (herdada do provider atual) é a região-alvo desta rede.
3. **Distribuição em 2 AZs** foi decisão de arquitetura (não especificada pelo usuário); assume-se que 2 AZs em `us-east-1` são aceitáveis e o mapeamento subnet↔AZ pode ser resolvido dinamicamente.
4. **NAT Gateway público na primeira AZ**; a subnet pública dessa AZ hospeda o NAT.
5. **State permanece local** neste ADR; migração de backend será tema de ADR separado.
6. **Sem requisitos de IPv6, compliance específico, RTO/RPO ou orçamento-teto** informados — assume-se contexto de workshop de baixo custo. Confirmar se algum desses vier a existir.

---

> **Bloqueado para implementação.** Este ADR aguarda revisão e aprovação humana.
> Para liberar a execução, edite o cabeçalho: `status: Aprovado`, preencha `aprovado_por` e `aprovado_em`, e faça commit em `docs/`.
