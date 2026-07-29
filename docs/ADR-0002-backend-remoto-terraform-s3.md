---
id: ADR-0002
titulo: Backend remoto do Terraform em S3 com versionamento, criptografia e state locking nativo (use_lockfile), provisionado pela stack 00-remote-backend-stack
status: Aprovado
data: 2026-07-25
substitui: N/A
aprovado_por: Kenerry Serain
aprovado_em: 2026-07-25
---

# ADR-0002 — Backend remoto do Terraform em S3

## 1. Contexto

O projeto `dvn-workshop-julho` mantém sua infraestrutura como código em `dvn-workshop-terraform/`, hoje organizada em **stacks numeradas**. Existe uma stack já implementada e aplicada:

- `dvn-workshop-terraform/01-networking-stack/` — a rede base definida no **ADR-0001** (`status: Aprovado`, aprovado por Kenerry Serain em 2026-07-25). Contém a VPC `10.0.0.0/24`, subnets públicas/privadas, IGW, NAT Gateway único e route tables, organizada no layout de arquivos `<dominio>.<componente>.tf` da rule `.claude/rules/terraform-naming.md`.

Estado atual relevante para este ADR:

- **A `01-networking-stack` usa state LOCAL** (`terraform.tfstate` no diretório do módulo). O state **não está mais vazio**: a stack foi aplicada e o `terraform.tfstate` contém **11 recursos** (serial 15), sem bloco `backend` (backend `none`/local). Ou seja, a rede já está no ar com state local — corrigindo a nota do ADR-0001 (que descrevia o state como vazio no momento em que foi escrito).
- Provider `hashicorp/aws` com constraint `~> 6.0`, lock em `6.56.0` (última versão, confirmada via MCP Terraform). Terraform CLI constraint `~> 1.10` no `versions.tf` da stack.
- Região parametrizada via `var.region` no `providers.tf` (não mais hardcoded como no início do ADR-0001), com `default_tags = var.default_tags`.
- Convenção de naming: tag `Name`/prefixo de projeto `dvn-bigode-`. Todo recurso de um ADR carrega a tag `adr=ADR-NNNN`.
- Não há backend remoto (S3) nem mecanismo de state locking em nenhuma stack.

Este ADR define a **fundação de state remoto**: uma nova stack `00-remote-backend-stack` que provisiona um bucket S3 para servir de **backend remoto (remote state)** das demais stacks. A numeração `00` é intencional — esta stack precede a `01` porque provê o recurso que as outras vão consumir. Este ADR **estabelece** o backend; a **migração** das stacks existentes (ex.: `01-networking-stack`) para esse backend é mencionada como consequência/evolução, mas **não** é executada por este ADR (será tratada por ADR próprio quando desejado).

### Requisitos definidos pelo usuário
- Criar um **bucket S3** para uso como backend remoto do Terraform (armazenamento do `terraform.tfstate`).
- **Versionamento habilitado** no bucket.
- Provisionar na **nova stack `00-remote-backend-stack`**, dentro de `dvn-workshop-terraform/`, seguindo o padrão de stacks numeradas já existente (hoje há `01-networking-stack`).

### Conflitos / divergências detectados com o contexto obrigatório
1. **Nenhum ADR anterior contradiz este pedido.** O ADR-0001 (Aprovado) explicitamente deixou a migração de backend remoto para "ADR próprio" (Seção 8 e Seção 12/Premissa 5 do ADR-0001). Este ADR-0002 é esse ADR dedicado. Não substitui o ADR-0001; complementa-o.
2. **Memória de agente desatualizada:** a nota de memória `infra-estado-atual` afirmava "tfstate vazio (0 recursos aplicados)". O estado real observado agora é 11 recursos aplicados na `01-networking-stack`. Isto será corrigido na memória; não altera a decisão deste ADR, mas reforça o **risco de state local** (state real, sem versionamento remoto nem lock, num arquivo local).

## 2. Drivers da decisão

Em ordem de prioridade para este contexto de workshop:

1. **Aderência à especificação do usuário** — bucket S3 como backend remoto, com versionamento habilitado, na stack `00-remote-backend-stack`.
2. **Durabilidade e recuperabilidade do state** — o state é o ativo mais crítico do Terraform; perdê-lo/corrompê-lo é o pior cenário. Versionamento e criptografia atendem a isso.
3. **Segurança do state** — o `terraform.tfstate` frequentemente contém dados sensíveis (IDs, às vezes secrets). Bloqueio de acesso público, criptografia em repouso e least privilege são obrigatórios.
4. **Prevenção de corrupção por concorrência (state locking)** — evitar que dois `apply` simultâneos corrompam o state.
5. **Simplicidade operacional e custo** — contexto de workshop; preferir o mínimo de peças móveis e o menor custo recorrente que ainda atenda aos drivers 2–4.

## 3. Opções consideradas

As opções abaixo tratam de **duas dimensões independentes** que compõem o backend: (A) **estratégia de state locking** e (B) **criptografia em repouso**. Em ambas, o bucket S3 com **versionamento habilitado**, **public access block** e **política de bucket** é premissa comum (é o requisito central do usuário e boa prática não negociável).

### Dimensão A — State locking

#### A1 — S3 native lockfile (`use_lockfile = true`) — escolhida
Locking nativo do S3, disponível **desde o Terraform 1.10.0** (confirmado via documentação AWS Prescriptive Guidance). O lock é um objeto de lockfile gravado no próprio bucket; não requer recurso adicional.

Trade-offs:
- **Custo**: zero recurso extra — sem tabela DynamoDB. Apenas o próprio bucket S3.
- **Operação**: menos peças móveis; um único recurso (bucket) provê state + lock.
- **Compatibilidade**: exige Terraform ≥ 1.10. A stack usa `~> 1.10` (constraint no `versions.tf`), **atende**. É a abordagem **recomendada** pela AWS; o DynamoDB locking está **deprecado** e será removido em versões futuras do Terraform (confirmado via doc AWS).

#### A2 — DynamoDB lock table (abordagem legada)
Tabela DynamoDB com chave primária `LockID`, referenciada no bloco `backend "s3"` via `dynamodb_table`.

Trade-offs:
- **Custo**: adiciona uma tabela DynamoDB (on-demand tem custo baixo, mas é recurso a mais para criar, tagear e destruir).
- **Operação**: mais um recurso no ciclo de vida da stack; mais uma coisa a versionar e destruir ao fim do workshop.
- **Status**: **deprecado** para backend S3 segundo a AWS; recomenda-se migrar para o native lockfile. Descartada por ser legada e adicionar custo operacional sem benefício neste contexto (Terraform já é ≥ 1.10).

#### A3 — Sem state locking
Não configurar locking algum.

Trade-offs:
- **Custo/simplicidade**: máximos — nada a criar.
- **Risco**: dois `apply` concorrentes podem **corromper o state**. Mesmo em workshop com um operador, CI/CD ou dois terminais tornam isso possível. Descartada por violar o driver 4 sem economia relevante frente à A1 (que também custa ~zero).

### Dimensão B — Criptografia em repouso (server-side encryption)

#### B1 — SSE-S3 (AES256, chave gerenciada pela AWS) — escolhida
Criptografia server-side com chaves gerenciadas pela AWS (`sse_algorithm = "AES256"`), via `aws_s3_bucket_server_side_encryption_configuration`.

Trade-offs:
- **Custo**: sem custo de KMS (sem cobrança por chave nem por requisição de KMS).
- **Segurança**: criptografa o state em repouso; atende ao driver 3 para contexto de workshop.
- **Controle**: **não** há controle granular de acesso à chave nem trilha de auditoria por uso de chave (isso é do KMS).

#### B2 — SSE-KMS (chave gerenciada pelo cliente, CMK)
Criptografia com chave KMS gerenciada pelo cliente.

Trade-offs:
- **Segurança/controle**: melhor — política de chave própria, auditoria de uso via CloudTrail, separação de quem pode descriptografar o state.
- **Custo/complexidade**: adiciona uma CMK (custo mensal por chave + custo por requisição de criptografia) e a necessidade de gerenciar a key policy; quem faz `terraform` precisa de permissão `kms:Decrypt`/`kms:GenerateDataKey`. Descartada para o workshop por custo/complexidade, mas **é a escolha recomendada para produção** (registrada como caminho de evolução).

## 4. Decisão

Provisionar, na nova stack **`00-remote-backend-stack`**, um **bucket S3** para backend remoto do Terraform com:

- **Versionamento habilitado** (requisito do usuário) — recurso separado `aws_s3_bucket_versioning` com `versioning_configuration { status = "Enabled" }` (confirmado via MCP: no provider AWS 6.x o versionamento é um recurso à parte do `aws_s3_bucket`).
- **State locking = A1: S3 native lockfile** (`use_lockfile = true` no bloco `backend "s3"` das stacks consumidoras). Nenhuma tabela DynamoDB.
- **Criptografia = B1: SSE-S3 (AES256)** via `aws_s3_bucket_server_side_encryption_configuration`.
- **Bloqueio de acesso público** via `aws_s3_bucket_public_access_block` com as quatro flags de bloqueio ativas.
- **Política de bucket** (`aws_s3_bucket_policy`) negando transporte não-cifrado (ex.: `aws:SecureTransport = false`), como reforço ao driver 3.

Justificativa frente aos drivers:
- **Driver 1**: entrega exatamente o pedido — bucket S3 versionado, na stack `00-remote-backend-stack`.
- **Driver 2** (durabilidade): versionamento habilita recuperação de versões anteriores do state em caso de corrupção/escrita acidental; S3 já provê durabilidade alta nativamente.
- **Driver 3** (segurança): public access block + SSE-S3 + bucket policy de transporte seguro cobrem o essencial em repouso e em trânsito.
- **Driver 4** (concorrência): native lockfile previne `apply` concorrente **sem** recurso extra.
- **Driver 5** (custo/simplicidade): a combinação A1+B1 tem o menor número de peças (só o bucket e suas configurações) e o menor custo recorrente (sem DynamoDB, sem KMS) que ainda satisfaz 2–4.

### Nome do bucket (unicidade global)
Nome de bucket S3 é **globalmente único** entre todas as contas AWS. Estratégia de naming adotada: compor o nome a partir de um **prefixo de projeto** + **identificadores de escopo** para garantir unicidade e legibilidade, no formato conceitual:

```
# ILUSTRATIVO — não copiar para o repositório
<prefixo-projeto>-<sufixo-proposito>-<account_id>-<region>
# ex.: dvn-bigode-tfstate-123456789012-us-east-1
```

- Incluir **account id** e **region** torna o nome praticamente único e evita colisão global.
- O `account_id` deve ser **resolvido dinamicamente** via data source `aws_caller_identity` (não hard-coded), e a região via a mesma variável do provider — coerente com a Seção 6 da rule (sem hard-coding).
- O nome final é **derivado em `locals`** a partir da variável de contexto do backend (ver Seção 6) e desses data sources; o resource nunca recebe uma string literal.

## 5. Consequências

Positivas:
- State passa a ter **durabilidade e histórico** (versionamento), **criptografia** em repouso e **proteção contra concorrência** (lockfile) — resolve a dívida de "state local" registrada no ADR-0001.
- Fundação reutilizável: qualquer stack futura (`01`, `02`, …) pode apontar seu `backend "s3"` para este bucket, usando **keys distintas** por stack (ex.: `00-remote-backend-stack/terraform.tfstate`, `01-networking-stack/terraform.tfstate`).
- Sem custo de DynamoDB nem de KMS.

Negativas / dívida técnica aceita:
- **Chicken-and-egg**: a própria stack que cria o backend não pode, no primeiro `apply`, usar o backend que ela ainda não criou. Ela **nasce com state local** e, após criar o bucket, **migra** seu próprio state para o bucket (`terraform init -migrate-state`). Sequência detalhada no plano (Seção 6). Aceito — é o padrão para bootstrap de backend.
- **SSE-S3 em vez de SSE-KMS**: sem auditoria/controle granular de chave. Aceito para workshop; evoluir para SSE-KMS exige novo ADR.
- **State das stacks existentes continua local até migração explícita**: este ADR **não** migra a `01-networking-stack`. Enquanto isso, o risco de state local da `01` permanece. A migração é um passo opcional documentado, a executar (idealmente por ADR/registro próprio) quando desejado.
- **Bucket com state é recurso "para sempre"**: destruí-lo apaga o histórico de state de todas as stacks que dependem dele. Exige proteção contra destruição acidental (ver Boas Práticas).

## 6. Plano de implementação

Passos atômicos, ordenados por dependência. Cada passo tem critério de conclusão verificável. O DevOps Engineer decide o "como escrever" (nomes de locals, uso de `for_each`, etc.). **A organização dos recursos em arquivos deve seguir o layout da Seção 7** (padrão `<dominio>.<componente>.tf` da rule `.claude/rules/terraform-naming.md`) e a **modelagem de variables deve seguir a Seção 6 da rule** (sem hard-coding; variável de contexto agrupada em objeto; valores concretos em `*.tfvars`).

0. **Criar o diretório da stack `dvn-workshop-terraform/00-remote-backend-stack/`** e os arquivos de esqueleto (`versions.tf`, `providers.tf`, `variables.tf`, `outputs.tf`) seguindo o mesmo padrão da `01-networking-stack` (provider `~> 6.0`, Terraform `~> 1.10`, `region = var.region`, `default_tags = var.default_tags`).
   *Conclusão:* `terraform init` (backend local, ainda sem bloco `backend`) e `terraform validate` limpos na nova stack.

1. **Modelar a variável de contexto do backend** conforme Seção 6 da rule: um objeto (ex.: `remote_state`/`backend`) com atributos como nome-base/propósito do bucket, flags de versionamento e criptografia, etc. Valores concretos em `terraform.tfvars`. Nenhum valor hard-coded nos resources. (arquivo: `variables.tf` + `terraform.tfvars`)
   *Conclusão:* `variables.tf` declara a variável com `description` e `type` objeto; `terraform.tfvars` traz os valores; `validate` limpo.

2. **Resolver `account_id` e região dinamicamente** via `data "aws_caller_identity"` (e a variável de região) e **derivar o nome do bucket em `locals`** (prefixo de projeto + propósito + account id + região). (arquivo: `s3.tf` ou `data.tf`/`locals.tf` conforme o Engineer organizar dentro do layout)
   *Conclusão:* `plan` mostra o nome do bucket resolvido no formato definido, sem string literal no resource.

3. **Criar o bucket S3** (`aws_s3_bucket`) com nome derivado no passo 2. (arquivo: `s3.tf` — recurso central do domínio `s3`)
   *Conclusão:* `plan` cria 1 `aws_s3_bucket` com o nome esperado e a tag `adr=ADR-0002`.

4. **Habilitar versionamento** com `aws_s3_bucket_versioning` (`versioning_configuration { status = "Enabled" }`) referenciando o bucket. (arquivo: `s3.backend-bucket-versioning.tf` ou agrupado em `s3.backend-bucket.tf` — ver Seção 7)
   *Conclusão:* `plan` cria 1 `aws_s3_bucket_versioning` com status `Enabled` para o bucket.

5. **Configurar criptografia server-side SSE-S3** com `aws_s3_bucket_server_side_encryption_configuration` (`sse_algorithm = "AES256"`). (arquivo: agrupado no mesmo componente do bucket — ver Seção 7)
   *Conclusão:* `plan` cria 1 `aws_s3_bucket_server_side_encryption_configuration` com AES256.

6. **Bloquear acesso público** com `aws_s3_bucket_public_access_block` (as quatro flags de bloqueio ativas). (arquivo: agrupado no mesmo componente do bucket)
   *Conclusão:* `plan` cria 1 `aws_s3_bucket_public_access_block` com bloqueio total.

7. **Aplicar política de bucket** (`aws_s3_bucket_policy`) negando acesso via transporte não seguro (condição `aws:SecureTransport = false`). (arquivo: agrupado no mesmo componente do bucket)
   *Conclusão:* `plan` cria 1 `aws_s3_bucket_policy` com a statement de negação de transporte inseguro.

8. **Expor outputs** do backend: nome do bucket, ARN do bucket e a região — para que outras stacks (e humanos) saibam para onde apontar seu `backend "s3"`. Nomes de output no padrão `{name}_{type}_{attribute}` da rule. (arquivo: `outputs.tf`)
   *Conclusão:* `terraform output` retorna nome/ARN/região do bucket após `apply`.

9. **Primeiro `apply` com state LOCAL** (resolve o chicken-and-egg): criar o bucket e suas configurações enquanto o state da própria stack ainda é local.
   *Conclusão:* `apply` conclui; o bucket existe; `terraform state list` mostra os recursos do backend no state **local**.

10. **Adicionar o bloco `backend "s3"` à própria `00-remote-backend-stack`** apontando para o bucket recém-criado, com `use_lockfile = true`, `key` própria (ex.: `00-remote-backend-stack/terraform.tfstate`), `region` e `encrypt = true`. (arquivo: `versions.tf` ou `backend.tf`)
    *Conclusão:* o bloco `backend "s3"` existe referenciando o bucket criado; `validate` limpo.

11. **Migrar o state local da stack para o backend S3**: `terraform init -migrate-state` (Terraform detecta a mudança de backend e oferece migrar o state existente).
    *Conclusão:* `init -migrate-state` conclui; o objeto de state aparece no bucket (na `key` definida); `terraform plan` **sem mudanças** (idempotência pós-migração); o `terraform.tfstate` local deixa de ser a fonte de verdade.

12. **Validar** (ver Seção 11).
    *Conclusão:* validações da Seção 11 passam.

> **Fora do escopo deste ADR (evolução opcional):** migrar a `01-networking-stack` para este backend. Se/quando desejado, seria: adicionar `backend "s3"` com `key = "01-networking-stack/terraform.tfstate"` e `use_lockfile = true` na `01`, rodar `terraform init -migrate-state`, e confirmar `plan` limpo. Recomenda-se registrar essa migração em ADR/nota própria, pois altera o backend de uma stack já Aprovada (ADR-0001).

## 7. Layout de diretórios

A organização física dos arquivos `.tf` **deve** seguir a rule `.claude/rules/terraform-naming.md`, **Seção 5 (Layout de arquivos)**: um recurso (ou grupo coeso de recursos do mesmo propósito) por arquivo, no padrão `<dominio>.<componente>.tf`, com prefixo de domínio consistente (`s3`) e sufixos descritivos em kebab-case. A nova stack espelha a organização e as convenções da `01-networking-stack`. Esta árvore é o **contrato de organização de arquivos** (obrigatório); o Engineer continua definindo os nomes internos do Terraform (locals, uso de `for_each`, etc.).

```
dvn-workshop-terraform/
├── 00-remote-backend-stack/            # NOVA stack — fundação de state remoto (precede a 01)
│   ├── s3.tf                           # recurso central do domínio: o bucket de state (aws_s3_bucket)
│   ├── s3.backend-bucket.tf            # config coesa do bucket: versioning + SSE-S3 + public access block + bucket policy
│   ├── variables.tf                    # variável de contexto do backend (objeto: propósito, flags versionamento/cripto); region; default_tags
│   ├── terraform.tfvars                # valores concretos (sem hard-coding nos resources)
│   ├── outputs.tf                      # nome/ARN/região do bucket (padrão {name}_{type}_{attribute})
│   ├── versions.tf                     # pin Terraform (~> 1.10) e provider (~> 6.0); recebe o bloco backend "s3" no passo 10
│   └── providers.tf                    # bloco provider (region = var.region, default_tags)
│
└── 01-networking-stack/                # stack existente (ADR-0001) — permanece com state LOCAL neste ADR
    └── ...                             # (inalterada por este ADR)
```

Observações:
- O agrupamento das configurações do bucket (versioning, encryption, public access block, policy) em `s3.backend-bucket.tf` segue o princípio de "grupo coeso de recursos do mesmo propósito por arquivo" da Seção 5. O Engineer **pode** separar em arquivos por componente (ex.: `s3.backend-bucket-versioning.tf`, `s3.backend-bucket-encryption.tf`) se preferir granularidade — desde que mantenha o prefixo de domínio `s3` e sufixos em kebab-case. O contrato é o padrão de nomes/domínio, não o número exato de arquivos.
- Nomes de **arquivos** usam `-` (dash) dentro de cada segmento (ex.: `backend-bucket`), conforme a exceção da Seção 5; **nomes internos do Terraform** usam `_` e não repetem o tipo do recurso (Seções 1–2).
- `variables.tf`, `outputs.tf`, `versions.tf`/`providers.tf` permanecem como arquivos convencionais na raiz da stack.
- O bloco `backend "s3"` (adicionado no passo 10) é config de estado, não recurso — pode viver em `versions.tf` (junto do `terraform {}`) ou num `backend.tf` dedicado, a critério do Engineer.

## 8. Boas práticas aplicáveis

- **Tag obrigatória de rastreabilidade**: **todo recurso AWS criado a partir deste ADR deve carregar a tag `adr=ADR-0002`.** Aplicar centralmente via `default_tags` no provider (não repetir em cada recurso).
- **Layout e nomenclatura de arquivos/código**: seguir a rule `.claude/rules/terraform-naming.md`. Layout físico conforme Seção 5 (`<dominio>.<componente>.tf`, ver Seção 7 deste ADR); nomes internos com `_`, sem repetir o tipo do recurso, substantivos no singular, `count`/`for_each` como primeiro argumento e `tags` como último (Seções 1–2); outputs no padrão `{name}_{type}_{attribute}` com `description` (Seções 3–4).
- **Modelagem de variables (Seção 6 da rule)**: **sem hard-coding** nos resources; usar uma **variável de contexto agrupada em objeto** (ex.: `remote_state`/`backend` com atributos de propósito e flags), com valores em `terraform.tfvars`. O nome do bucket é **derivado em `locals`** a partir dessa variável + `aws_caller_identity` + região, nunca uma string literal.
- **Tagging/naming**: manter o prefixo de projeto `dvn-bigode-` na tag `Name` e no nome do bucket (ex.: `dvn-bigode-tfstate-...`), coerente com a `01-networking-stack`.
- **Segurança do state (least privilege + defense in depth)**:
  - `aws_s3_bucket_public_access_block` com as **quatro** flags de bloqueio ativas.
  - **Criptografia em repouso** SSE-S3 (AES256); `encrypt = true` também no bloco `backend "s3"`.
  - **Bucket policy** negando transporte não seguro (`aws:SecureTransport = false`).
  - Acesso ao bucket restrito ao principal que roda o Terraform (least privilege) — evitar policies amplas.
- **Versionamento**: habilitado (requisito) — permite recuperar versões anteriores do state em caso de corrupção. Após habilitar versionamento pela primeira vez, a AWS recomenda **aguardar ~15 min** antes de escritas (confirmado via MCP); relevante porque as stacks consumidoras passarão a escrever state logo em seguida.
- **State locking**: `use_lockfile = true` no `backend "s3"` (nativo, Terraform ≥ 1.10) — **sem DynamoDB**.
- **Proteção contra destruição acidental**: recomenda-se `lifecycle { prevent_destroy = true }` no bucket de state (é o repositório de state de todas as stacks). O Engineer aplica; se um `destroy` intencional for necessário no fim do workshop, remove-se a proteção deliberadamente.
- **Keys por stack**: cada stack usa uma `key` distinta no mesmo bucket (ex.: `<nome-da-stack>/terraform.tfstate`) para isolar os states.
- **Versionamento de provider/Terraform**: manter os pins `~> 6.0` e `~> 1.10` já usados na `01`; não fazer upgrade dentro deste ADR.

## 9. Riscos e mitigações

- **Chicken-and-egg no bootstrap** — a stack cria o backend que ela mesma vai usar. Mitigação: sequência explícita (passos 9→10→11): aplicar com state local, depois migrar. Aceito.
- **Perda/destruição do bucket de state** — apagaria o histórico de state de todas as stacks. Mitigação: `prevent_destroy = true` + versionamento + block public access. Aceito como recurso "para sempre".
- **State local da `01-networking-stack` permanece** até migração explícita (fora de escopo) — risco de perda/conflito do `terraform.tfstate` local da `01` (que já tem 11 recursos reais). Mitigação: migração recomendada como passo seguinte; enquanto isso, não editar o state local manualmente e considerar backup do arquivo.
- **Custo de versionamento** — versões antigas de state acumulam objetos no bucket. Mitigação (opcional, fora do escopo): lifecycle rule para expirar versões não-atuais antigas; para workshop o volume é desprezível.
- **`use_lockfile` exige Terraform ≥ 1.10** — a stack usa `~> 1.10`, atende; mas se alguém rodar com CLI < 1.10 o lock falha. Mitigação: manter o `required_version` e documentar.
- **[NÃO VERIFICADO] Custo mensal de S3 (armazenamento + requisições) para o state em `us-east-1`** — não quantificado via MCP nesta sessão; para workshop é ordem de centavos, mas confirmar na calculadora AWS antes de aprovar orçamento.
- **[NÃO VERIFICADO] Comportamento exato de `terraform init -migrate-state` do local para o S3 nesta versão de CLI** — o fluxo é o padrão documentado, mas a execução real (prompts, confirmação) deve ser observada pelo Engineer no `init`. Marcar como ponto de atenção operacional.
- **[NÃO VERIFICADO] Nome de bucket globalmente único disponível** — a estratégia (prefixo + account id + região) torna colisão improvável, mas a unicidade global só é confirmada no `apply`. Se colidir, ajustar o sufixo.

## 10. Rollback

- **Passos 3–7 (bucket e configs)**: enquanto o state ainda é local (antes do passo 11), o rollback é `terraform destroy` da stack (ou remover os recursos do código e reaplicar). Se `prevent_destroy = true` já estiver ativo, é preciso removê-lo deliberadamente antes do destroy.
- **Passo 11 (migração de state para o S3)**: para reverter, reconfigurar o `backend` de volta para local (remover/alterar o bloco `backend "s3"`) e rodar `terraform init -migrate-state` novamente, trazendo o state de volta ao arquivo local. O objeto no bucket permanece (versionado) — pode ser removido manualmente depois.
- **Destruir tudo (fim do workshop)**: só é seguro após confirmar que **nenhuma** stack depende mais deste bucket. Ordem: garantir stacks consumidoras migradas de volta a local (ou destruídas) → remover `prevent_destroy` → esvaziar versões do bucket → `terraform destroy` da `00-remote-backend-stack`.
- **Versionamento**: não pode ser retornado a "unversioned" pela API S3 (confirmado via MCP: mudar status para `Disabled` após `Enabled`/`Suspended` gera erro). Para "desligar", usa-se `Suspended`, não `Disabled`. Isto limita o rollback do versionamento a suspender, não remover.

## 11. Validação

O DevOps Engineer deve comprovar ao final:

1. `terraform validate` e `terraform fmt -check` limpos na `00-remote-backend-stack`.
2. Bucket S3 criado com o nome no formato definido (prefixo de projeto + account id + região), **globalmente único**.
3. **Versionamento = Enabled** no bucket (verificável no console ou `aws s3api get-bucket-versioning`).
4. **Criptografia SSE-S3 (AES256)** configurada (`get-bucket-encryption`).
5. **Public access block** com as quatro flags ativas (`get-public-access-block`).
6. **Bucket policy** presente negando `aws:SecureTransport = false`.
7. State da própria `00-remote-backend-stack` **migrado para o S3**: objeto de state presente na `key` definida no bucket; `terraform plan` **sem mudanças** após a migração (idempotência).
8. **State locking funcional**: com `use_lockfile = true`, um segundo `apply/plan` concorrente é bloqueado enquanto o primeiro segura o lock (ou o lockfile aparece transitoriamente no bucket durante uma operação).
9. Todos os recursos com a tag `adr=ADR-0002` (verificável via `terraform state show` ou console).
10. `terraform output` retorna nome/ARN/região do bucket.
11. (Se `prevent_destroy` aplicado) confirmar que um `terraform destroy` é bloqueado pelo lifecycle enquanto a proteção estiver ativa.

## 12. Premissas

Como o pedido foi para planejar diretamente, registro as premissas — cada uma é ponto de validação humana antes/na aprovação:

1. **Região `us-east-1`** (herdada da `01-networking-stack` via `var.region`) é a região-alvo do bucket de state. Confirmar.
2. **Conta única** (single account) — o bucket serve às stacks desta mesma conta AWS; não há requisito multi-conta informado. Confirmar.
3. **SSE-S3 (AES256)** é criptografia suficiente para este workshop; SSE-KMS fica para produção/ADR futuro. Confirmar se há requisito de compliance que exija CMK.
4. **State locking via native lockfile** (Terraform ≥ 1.10, já em uso) é aceitável; sem DynamoDB. Confirmar.
5. **Este ADR NÃO migra a `01-networking-stack`** para o backend remoto; a `01` permanece com state local até uma migração explícita futura. Confirmar se o usuário deseja que a migração da `01` entre no escopo (nesse caso, este ADR deve ser ampliado ou um ADR complementar criado).
6. **Sem requisitos de RTO/RPO, orçamento-teto ou compliance específico** informados — assume-se contexto de workshop de baixo custo. Confirmar se algum existir.

---

> **Bloqueado para implementação.** Este ADR aguarda revisão e aprovação humana.
> Para liberar a execução, edite o cabeçalho: `status: Aprovado`, preencha `aprovado_por` e `aprovado_em`, e faça commit em `docs/`.
