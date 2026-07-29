---
id: ADR-0003
titulo: Cluster Amazon EKS na nova stack 02-eks-cluster-stack, provisionado com recursos NATIVOS do provider hashicorp/aws (sem módulo comunitário), com node group ON_DEMAND t3.medium, authentication_mode API_AND_CONFIG_MAP e acesso admin do principal atual via EKS Access Entry
status: Aprovado
data: 2026-07-26
substitui: N/A
aprovado_por: Kenerry Serain
aprovado_em: 2026-07-26
---

# ADR-0003 — Cluster Amazon EKS (stack `02-eks-cluster-stack`)

## 1. Contexto

O projeto `dvn-workshop-julho` mantém a infraestrutura como código em `dvn-workshop-terraform/`, organizada em **stacks numeradas**. Estado atual verificado nesta sessão (lendo os arquivos das stacks e os ADRs em `docs/`):

- **`00-remote-backend-stack`** — bucket S3 de backend remoto (**ADR-0002**, `status: Aprovado`, Kenerry Serain, 2026-07-25). Bucket real observado no `versions.tf`: `dvn-bigode-tfstate-654654554686-us-east-1`. Logo, **account id = `654654554686`**, região `us-east-1`.
- **`01-networking-stack`** — VPC `10.0.0.0/24` (**ADR-0001**, `status: Aprovado`). Já **migrada para o backend remoto S3**: seu `versions.tf` contém `backend "s3"` com `key = "01-networking-stack/terraform.tfstate"`, `use_lockfile = true`, `encrypt = true`. Isso **atualiza** o que o ADR-0002 registrava como "state local da 01" — a migração já ocorreu.
- Convenções verificadas na `01`:
  - Provider `hashicorp/aws` `~> 6.0`; Terraform CLI `~> 1.10`. Provider com `region = var.region` e `default_tags = var.default_tags`.
  - Prefixo de projeto `dvn-bigode-`; `default_tags = { Environment = "production", Project = "dvn-workshop-julho" }`.
  - Modelagem de variáveis por **objeto de contexto agrupado** (`variable "vpc"` do tipo `object`), valores em `terraform.tfvars`, sem hard-coding nos resources (rule `.claude/rules/terraform-naming.md`, Seção 6).
  - Layout físico `<dominio>.<componente>.tf`.
- **Outputs expostos pela `01-networking-stack`** (contrato de consumo entre stacks), verificados em `outputs.tf`:
  - `vpc_id` (string)
  - `vpc_cidr_block` (string)
  - `public_subnet_ids` — **map** `{ nome_da_subnet => id }`
  - `private_subnet_ids` — **map** `{ nome_da_subnet => id }`
  - `internet_gateway_id`, `nat_gateway_id`, `nat_eip_public_ip`
  - As subnets privadas estão em **duas AZs** (`us-east-1a`, `us-east-1b`), CIDRs `10.0.0.128/26` e `10.0.0.192/26`; as públicas em `10.0.0.0/26` e `10.0.0.64/26`.

Este ADR define a **nova stack `02-eks-cluster-stack`** que provisiona um **cluster Amazon EKS** consumindo os outputs da `01-networking-stack` via **`terraform_remote_state`** (data source lendo o mesmo bucket S3). A numeração `02` segue a sequência e a dependência (EKS depende da rede).

### Requisitos definidos pelo usuário
1. Cluster EKS provisionado via Terraform.
2. Node group **ON_DEMAND** (`capacity_type = "ON_DEMAND"`, não Spot).
3. Instância **t3.medium**.
4. **2 workers** (`desired_size = 2`); min/max sensatos a justificar.
5. **Control plane logging habilitado** (avaliar quais log types: api, audit, authenticator, controllerManager, scheduler).
6. Usar a **versão mais recente** do Kubernetes suportada pelo EKS — citar a versão concreta verificada via MCP/docs.
7. **IAM** necessário: cluster role, node role, políticas gerenciadas, e IRSA/OIDC provider se aplicável.
8. Habilitar **`API_AND_CONFIG_MAP`** (access config authentication mode que suporta aws-auth ConfigMap e EKS Access Entries via API).
9. Garantir que **o principal atual** (quem roda o Terraform) acesse o cluster — via **EKS Access Entry** com política admin (`AmazonEKSClusterAdminPolicy`) e/ou aws-auth.

### Fatos verificados via MCP / docs oficiais (2026-07-26)
- **Versão mais recente do Kubernetes no EKS: `1.36`** (AWS docs — Kubernetes version lifecycle; standard support atual: `1.36`, `1.35`, `1.34`, `1.33`; EKS release do `1.36` em 2026-06-02, fim de standard support 2027-08-02). É a versão-alvo deste ADR.
- **Provider `hashicorp/aws`**: última `6.56.0` (MCP Terraform). Pin do projeto `~> 6.0` — mantido. Todos os recursos abaixo foram confirmados via MCP `get_provider_details` na `6.56.0`, refletindo a documentação oficial do Terraform Registry (hashicorp/aws).

Recursos e argumentos **nativos** confirmados (nomes exatos — não escrever de memória):

- **`aws_eks_cluster`** (docID 12941989):
  - Argumentos obrigatórios: `name`, `role_arn`, `vpc_config`.
  - `vpc_config { subnet_ids (obrigatório, >= 2 AZs), endpoint_private_access (default false), endpoint_public_access (default true), public_access_cidrs, security_group_ids }`.
  - `access_config { authentication_mode, bootstrap_cluster_creator_admin_permissions }`. `authentication_mode` aceita `CONFIG_MAP` | `API` | `API_AND_CONFIG_MAP`. **`bootstrap_cluster_creator_admin_permissions` (default `true`)** é o **equivalente nativo** ao `enable_cluster_creator_admin_permissions` do módulo — concede admin ao principal que cria o cluster **sem precisar do ARN** (resolve o requisito 9).
  - **`enabled_cluster_log_types`** — lista dos log types do control plane (nome exato **`enabled_cluster_log_types`**, não `enabled_log_types` nem `cluster_enabled_log_types`). Valores: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`.
  - **`version`** — versão do Kubernetes (nome do argumento é `version`, não `kubernetes_version`). Downgrade não suportado pela AWS.
  - `tags` propaga `default_tags`. Exporta: `arn`, `endpoint`, `certificate_authority.data`, `identity[0].oidc[0].issuer` (URL do issuer OIDC, base para IRSA), `status`, `platform_version`.
- **`aws_eks_node_group`** (docID 12941992):
  - Obrigatórios: `cluster_name`, `node_role_arn`, `subnet_ids`, `scaling_config`.
  - `scaling_config { desired_size (obrig.), max_size (obrig.), min_size (obrig.) }`.
  - `capacity_type` — `ON_DEMAND` | `SPOT`. `instance_types` — lista (default `["t3.medium"]`). `update_config { max_unavailable | max_unavailable_percentage }`. `version` (default = versão do cluster).
  - Exporta `arn`, `status`, `resources.autoscaling_groups`.
- **`aws_iam_role` + `aws_iam_role_policy_attachment`** (nativos): cluster role assume `eks.amazonaws.com` (`sts:AssumeRole` + `sts:TagSession`); node role assume `ec2.amazonaws.com` (`sts:AssumeRole`). Managed policies confirmadas nos exemplos oficiais:
  - Cluster role: `arn:aws:iam::aws:policy/AmazonEKSClusterPolicy` (e, quando aplicável, `AmazonEKSVPCResourceController`).
  - Node role: `arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy`, `arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy`, `arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly`.
  - O `aws_eks_cluster`/`aws_eks_node_group` devem ter `depends_on` nos `aws_iam_role_policy_attachment` correspondentes (documentado nos exemplos oficiais — sem isso o EKS não consegue deletar a infra EC2 gerenciada).
- **`aws_eks_access_entry`** (docID 12941985): `cluster_name` (obrig.), `principal_arn` (obrig.), `type` (default `STANDARD`), `kubernetes_groups`, `user_name`.
- **`aws_eks_access_policy_association`** (docID 12941986): `cluster_name`, `policy_arn`, `principal_arn`, `access_scope { type (`namespace`|`cluster`), namespaces }`. Para admin de cluster: `policy_arn = arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy` com `access_scope { type = "cluster" }` (AWS docs — equivale a `system:masters`; adequado para workshop).
- **`aws_iam_openid_connect_provider`** (docID 12942122) + **`data "tls_certificate"`** (provider `hashicorp/tls`): materializam o **OIDC provider (IRSA)** que o módulo faria via `enable_irsa`. Padrão oficial: `data "tls_certificate"` lê o `identity[0].oidc[0].issuer` do cluster para obter o thumbprint; o `aws_iam_openid_connect_provider` usa `url = issuer`, `client_id_list = ["sts.amazonaws.com"]`, `thumbprint_list = [data.tls_certificate...sha1_fingerprint]`. **[NÃO VERIFICADO nesta sessão]** o docID exato do `tls_certificate` (provider `tls`) e os nomes de atributo `sha1_fingerprint`/`certificates` — o Engineer deve confirmar via MCP do provider `hashicorp/tls` antes de escrever; registrado nos Riscos.
- **`aws_cloudwatch_log_group`** (docID 12941662): se for desejado gerenciar explicitamente o log group do control plane. O EKS grava em `/aws/eks/<cluster-name>/cluster`; criar o log group via Terraform permite controlar `retention_in_days` e KMS. Deve ser criado **antes** do cluster (`depends_on`) para o Terraform ser dono do recurso e evitar conflito com o log group que o EKS criaria sozinho.

### Conflitos / divergências detectados com o contexto obrigatório
1. **Nenhum ADR anterior contradiz este pedido.** ADR-0001 e ADR-0002 estão `Aprovado` e são pré-requisitos (rede + backend). Este ADR **não substitui** nenhum; **depende** de ambos.
2. **Divergência factual corrigida:** o ADR-0002 registrava a `01-networking-stack` como "state local". O `versions.tf` atual da `01` **já** tem `backend "s3"` — a migração ocorreu. Não altera a decisão; apenas confirma que o backend remoto está disponível para a `02` usar o mesmo padrão de `key` por stack.
3. **Requisito 9 depende do ARN do principal atual, NÃO VERIFICADO nesta sessão** (o AWS MCP pediu reautorização/token expirado e o AWS CLI local está sem credenciais — `Unable to locate credentials`). Ver Riscos e Premissas. O argumento nativo `access_config.bootstrap_cluster_creator_admin_permissions = true` cobre o caso comum sem exigir o ARN.

## 2. Drivers da decisão

Em ordem de prioridade para este contexto de workshop:

1. **Aderência à especificação do usuário** — EKS gerenciado, node group ON_DEMAND `t3.medium`, `desired_size = 2`, logging habilitado, K8s mais recente, `API_AND_CONFIG_MAP`, acesso admin do principal atual.
2. **Acesso garantido ao cluster no dia 1** — se quem provisiona não conseguir `kubectl`, o cluster é inútil. É requisito duro (9).
3. **Segurança / least privilege** — IAM correto (cluster/node roles com apenas as managed policies necessárias), IRSA para cargas futuras, endpoint com exposição controlada, logging para auditoria.
4. **Controle total e independência de módulo comunitário** — decisão explícita do usuário de usar **somente recursos nativos/oficiais do provider `hashicorp/aws`**, sem a abstração `terraform-aws-modules/eks/aws`. Prioriza transparência do que é criado, ausência de pin de módulo de terceiros e alinhamento didático (workshop) com os recursos oficiais do Terraform Registry, aceitando em troca mais código IAM/OIDC escrito à mão.
5. **Custo previsível e baixo** — 2× `t3.medium` ON_DEMAND + 1 control plane EKS; evitar recursos supérfluos.
6. **Consistência com as stacks existentes** — mesmo backend S3 (key por stack), mesmos pins de provider/Terraform, mesmo padrão de naming/tagging e de modelagem de variáveis por objeto.

## 3. Opções consideradas

Duas dimensões independentes de decisão: **(A) como escrever o EKS** (módulo oficial vs. recursos nativos) e **(B) como garantir o acesso do principal atual** (requisito 9). O restante (ON_DEMAND `t3.medium`, `desired_size=2`, logging, K8s 1.36, `API_AND_CONFIG_MAP`, IRSA) é requisito fixo, não opção.

### Dimensão A — Forma de provisionar o EKS

#### A1 — Recursos nativos do provider `hashicorp/aws` (`aws_eks_cluster` + `aws_eks_node_group` + IAM + OIDC + access entries à mão) — **escolhida**
Escrever tudo com os recursos oficiais do provider, conforme a documentação do Terraform Registry (hashicorp/aws), confirmados via MCP (ver "Fatos verificados"). Componentes:
- `aws_eks_cluster` (com `vpc_config`, `access_config`, `enabled_cluster_log_types`, `version`);
- `aws_eks_node_group` (com `scaling_config`, `capacity_type`, `instance_types`);
- `aws_iam_role` + `aws_iam_role_policy_attachment` para o **cluster role** (`AmazonEKSClusterPolicy`, `AmazonEKSVPCResourceController`) e para o **node role** (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`);
- `aws_eks_access_entry` + `aws_eks_access_policy_association` para acesso do principal atual (complementando o `bootstrap_cluster_creator_admin_permissions`);
- `aws_iam_openid_connect_provider` + `data "tls_certificate"` para o **OIDC provider (IRSA)**;
- `aws_cloudwatch_log_group` para os logs do control plane (opcional, para controlar retenção/KMS).

Trade-offs:
- **Controle e transparência**: máximos; nenhuma abstração intermediária, nenhum pin de módulo de terceiros. Cada recurso criado é explícito no código — valioso didaticamente no workshop.
- **Independência**: sem acoplamento a versões/changelog de um módulo comunitário; upgrades dependem só do provider `~> 6.0`.
- **Custo operacional**: **mais alto** que o módulo — é preciso escrever manualmente os dois IAM roles com as managed policies, o `aws_iam_openid_connect_provider` com o thumbprint (via `data tls_certificate`), as access entries e os `depends_on` corretos entre policy attachments e cluster/node group. Mais linhas e mais pontos de atenção. **Aceito** por decisão do usuário (driver 4).
- **Segurança**: mesma capacidade do módulo, porém mais suscetível a erro humano (ex.: esquecer uma managed policy no node role e o node não entra no cluster; thumbprint OIDC incorreto). Mitigado seguindo os exemplos oficiais confirmados via MCP e pelos `depends_on` documentados.
- **Custo (AWS)**: idêntico ao módulo — a diferença é só de código/operação, não de recurso provisionado.

#### A2 — Módulo `terraform-aws-modules/eks/aws` v21.x — **descartada**
Módulo comunitário oficial da HashiCorp/AWS-IA, amplamente adotado (última `21.24.0`, exige provider aws `>= 6.52`, compatível com o lock `6.56.0`). Encapsularia cluster, cluster/node IAM roles, OIDC provider (IRSA via `enable_irsa`), access entries (`enable_cluster_creator_admin_permissions` / `access_entries`) e node groups (`eks_managed_node_groups`), reduzindo drasticamente o código próprio.

Trade-offs:
- **Custo operacional**: baixo — menos código IAM/OIDC para escrever e manter.
- **Segurança**: defaults sensatos, menos erro humano em IAM/OIDC.
- **Complexidade/acoplamento**: superfície de configuração grande e **dependência de um módulo comunitário pinado**, com changelog próprio a acompanhar em upgrades.

**Descartada (A2) por decisão explícita do usuário**: o requisito é usar **somente recursos nativos/oficiais do provider**, sem módulo comunitário — para máxima transparência, independência de terceiros e alinhamento didático do workshop com os recursos do Terraform Registry. O custo AWS é idêntico; a diferença é apenas o maior esforço de código (aceito). Fica registrada como caminho de menor esforço operacional caso o time reveja essa decisão no futuro (via novo ADR).

### Dimensão B — Acesso admin do principal atual (requisito 9)

Contexto: com `authentication_mode = API_AND_CONFIG_MAP`, o cluster aceita **tanto** Access Entries (API) quanto o `aws-auth` ConfigMap. As opções abaixo diferem em **como** conceder admin a quem roda o Terraform.

#### B1 — `access_config.bootstrap_cluster_creator_admin_permissions = true` (access entry automática para o criador) — **escolhida (base)**
No `aws_eks_cluster`, o bloco `access_config` com `bootstrap_cluster_creator_admin_permissions = true` (default `true`, confirmado via MCP) faz o EKS criar automaticamente uma **access entry** para o principal que executa o Terraform, com permissões de admin de cluster.

Trade-offs:
- **Robustez**: garante que quem aplica **sempre** tem admin, sem precisar descobrir/hard-codear o ARN.
- **Segurança**: concede acesso amplo (equivalente a `system:masters`) ao criador — aceitável para workshop; em produção preferir escopo mais restrito.
- **Limitação**: cobre **apenas** o principal que roda o `apply`. Se outro principal precisar de acesso, use B2.

#### B2 — `aws_eks_access_entry` + `aws_eks_access_policy_association` explícitas para ARNs nomeados — **escolhida (complementar, condicional)**
Declarar, com os **recursos nativos**, um `aws_eks_access_entry` (`principal_arn`, `type = "STANDARD"`) e um `aws_eks_access_policy_association` (`policy_arn = arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy`, `access_scope { type = "cluster" }`) por ARN. Modelado como **variável de contexto** (lista/map de objetos com `principal_arn` + policy), iterado com `for_each`, valores em `terraform.tfvars`.

Trade-offs:
- **Flexibilidade**: concede acesso a qualquer ARN (roles de CI, outros operadores) de forma declarativa e auditável.
- **Dependência**: exige conhecer os ARNs — e o ARN do principal atual **não foi verificado nesta sessão** (credenciais indisponíveis). Por isso B2 é **complementar/condicional**: se o principal que roda o Terraform for exatamente quem precisa de admin, **B1 já basta**; B2 entra se houver ARNs adicionais ou se o time preferir declarar o admin explicitamente.

#### B3 — Apenas `aws-auth` ConfigMap (modo legado)
Gerenciar acesso só pelo ConfigMap `aws-auth`.

Trade-offs:
- **Compatibilidade**: funciona (o modo `API_AND_CONFIG_MAP` mantém o ConfigMap ativo).
- **Operação**: **desencorajado** pela AWS em favor de Access Entries; editar `aws-auth` é propenso a erro (um typo pode travar o acesso de todos). **Descartada como mecanismo primário**; permanece disponível como fallback justamente porque o `authentication_mode` escolhido mantém o ConfigMap habilitado.

**Decisão da dimensão B: B1 como base (garantia para o criador, via `bootstrap_cluster_creator_admin_permissions = true`) + B2 disponível e parametrizado (recursos nativos `aws_eks_access_entry`/`aws_eks_access_policy_association`) para ARNs adicionais.** `aws-auth` (B3) fica como fallback do modo `API_AND_CONFIG_MAP`, não como mecanismo primário.

## 4. Decisão

Provisionar, na nova stack **`02-eks-cluster-stack`**, um **cluster Amazon EKS** usando **exclusivamente recursos nativos do provider `hashicorp/aws` `~> 6.0`** (sem módulo comunitário), conforme a documentação oficial do Terraform Registry, consumindo a rede da `01-networking-stack` via `terraform_remote_state` no mesmo bucket S3. Configuração:

- **Versão do Kubernetes: `1.36`** (a mais recente em standard support no EKS, verificada via docs). Passada no argumento **`version`** do `aws_eks_cluster`. Parametrizada em variável (não hard-coded no recurso).
- **Rede**: cluster nas **subnets privadas** da `01` (control plane ENIs e nodes em subnets privadas). Consumir `private_subnet_ids` (map → lista de valores) e `vpc_id` do remote state, populando `vpc_config.subnet_ids` do cluster e `subnet_ids` do node group. As subnets privadas já cobrem 2 AZs (`us-east-1a`/`us-east-1b`), atendendo ao mínimo de multi-AZ do EKS.
- **Cluster IAM role** (`aws_iam_role` + `aws_iam_role_policy_attachment`): trust em `eks.amazonaws.com` (`sts:AssumeRole` + `sts:TagSession`); anexar `AmazonEKSClusterPolicy` e `AmazonEKSVPCResourceController`. Referenciado em `role_arn` do cluster, com `depends_on` nos attachments.
- **Node IAM role** (`aws_iam_role` + `aws_iam_role_policy_attachment`): trust em `ec2.amazonaws.com` (`sts:AssumeRole`); anexar `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`. Referenciado em `node_role_arn` do node group, com `depends_on` nos attachments.
- **Managed node group** (`aws_eks_node_group`), um grupo:
  - `capacity_type = "ON_DEMAND"` (requisito 2)
  - `instance_types = ["t3.medium"]` (requisito 3)
  - `scaling_config { desired_size = 2, min_size = 2, max_size = 4 }` (requisito 4) — **justificativa**: `min = 2` mantém a capacidade desejada mesmo se um node falhar/for substituído, preservando distribuição em 2 AZs (1 por AZ no mínimo); `max = 4` dá folga (2×) para eventual scaling manual/rolling update sem reescrever a stack, sem inflar custo por já subir em 4. `desired = min` evita que um scale-in reduza abaixo do pedido.
  - `update_config { max_unavailable = 1 }` para rolling update controlado.
- **Control plane logging habilitado** (requisito 5) via **`enabled_cluster_log_types`** do `aws_eks_cluster`. **Decisão: habilitar os cinco tipos** — `["api", "audit", "authenticator", "controllerManager", "scheduler"]`. Justificativa: em workshop o volume/custo de CloudWatch Logs é baixo e ter **audit + authenticator** é essencial para depurar problemas de acesso (requisito 9); os demais ajudam a entender o control plane. Parametrizado em variável para permitir reduzir depois.
- **CloudWatch log group** (`aws_cloudwatch_log_group`) para `/aws/eks/<cluster-name>/cluster`, criado antes do cluster (`depends_on`) para o Terraform ser dono do recurso e controlar `retention_in_days`. Parametrizável; se o time preferir deixar o EKS criar o log group implicitamente, este recurso pode ser omitido (registrado como opcional).
- **`access_config.authentication_mode = "API_AND_CONFIG_MAP"`** (requisito 8) — explícito no bloco `access_config` do `aws_eks_cluster`.
- **IRSA / OIDC** (requisito 7): `data "tls_certificate"` lê o `identity[0].oidc[0].issuer` do cluster; `aws_iam_openid_connect_provider` cria o OIDC provider (`url = issuer`, `client_id_list = ["sts.amazonaws.com"]`, `thumbprint_list` a partir do fingerprint do `tls_certificate`). Habilita ServiceAccounts com IAM roles (IRSA) para cargas futuras.
- **Acesso do principal atual** (requisito 9): **`access_config.bootstrap_cluster_creator_admin_permissions = true`** (B1) + variável opcional para `aws_eks_access_entry` + `aws_eks_access_policy_association` (B2) para ARNs adicionais, cada um com `AmazonEKSClusterAdminPolicy` escopo `cluster` (`arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy`).
- **Endpoint** (`vpc_config`): `endpoint_private_access = true`; `endpoint_public_access` inicialmente **`true`** apenas para permitir `kubectl` do operador de fora da VPC durante o workshop (parametrizado; ver Riscos). Se o time operar de dentro da VPC, setar público `false` e/ou restringir `public_access_cidrs`.

Justificativa frente aos drivers:
- **Driver 1**: entrega exatamente o pedido (ON_DEMAND `t3.medium`, `desired=2`, logging, K8s 1.36, `API_AND_CONFIG_MAP`, admin do criador).
- **Driver 2**: `bootstrap_cluster_creator_admin_permissions = true` garante acesso do operador no dia 1 sem depender de descobrir ARN.
- **Driver 3**: IRSA via OIDC provider nativo, IAM roles com apenas as managed policies mínimas do EKS, logging completo para auditoria, nodes em subnets privadas.
- **Driver 4**: **somente recursos nativos/oficiais do provider**, sem módulo comunitário — controle e transparência totais, sem pin de terceiros. É a decisão central deste ADR.
- **Driver 5**: 2× `t3.medium` ON_DEMAND + 1 control plane; sem recursos extras.
- **Driver 6**: mesma `key`-por-stack no bucket existente, mesmos pins, mesmo naming/tagging e modelagem por objeto.

## 5. Consequências

Positivas:
- Cluster EKS gerenciado, multi-AZ (nodes em 2 AZs), com IRSA pronto para cargas que precisem de IAM por ServiceAccount.
- Acesso admin garantido a quem provisiona, sem manipular `aws-auth` manualmente.
- **Zero dependência de módulo comunitário**: todo o cluster é composto por recursos oficiais do provider `hashicorp/aws`, com controle e transparência totais e sem changelog de terceiros para acompanhar. Alinhamento didático do workshop com a documentação oficial do Terraform Registry.
- Logging completo do control plane para auditoria/depuração.
- Padrão reutilizável: futuras stacks podem consumir os outputs desta (`cluster_name`, `cluster_endpoint`, `oidc_provider_arn`, etc.) via remote state.

Negativas / dívida técnica aceita:
- **Mais código próprio para escrever e manter**: dois IAM roles com policy attachments, OIDC provider com thumbprint (via `data tls_certificate`), access entries e os `depends_on` corretos são responsabilidade da stack. Mais superfície para erro humano (ex.: managed policy faltando no node role; thumbprint OIDC incorreto). Aceito por decisão do usuário; mitigado seguindo os exemplos oficiais confirmados via MCP.
- **`AmazonEKSClusterAdminPolicy` = `system:masters`**: acesso amplo. Aceito para workshop; produção deveria usar escopo por namespace / least privilege.
- **`endpoint_public_access = true`** (se mantido): a API do cluster fica acessível pela internet (mesmo autenticada). Dívida de segurança aceita para conveniência do workshop; mitigável com `public_access_cidrs` restrito ou desligando o público.
- **Custo recorrente**: control plane EKS + 2× `t3.medium` ON_DEMAND rodam 24/7 até destruir a stack. Aceito; workshop deve destruir ao fim.
- **Logging dos 5 tipos**: gera CloudWatch Logs contínuo (custo pequeno mas não nulo). Aceito; parametrizado para reduzir.
- **Dependência adicional do provider `hashicorp/tls`** (para o `data tls_certificate` do thumbprint OIDC): precisa ser declarado em `versions.tf`. Aceito; é provider oficial HashiCorp.

## 6. Plano de implementação

Passos atômicos, ordenados por dependência. Cada passo tem critério de conclusão verificável. O DevOps Engineer decide o "como escrever" (nomes de locals, `for_each`, etc.). **A organização em arquivos deve seguir a Seção 7** (padrão `<dominio>.<componente>.tf` da rule) e a **modelagem de variáveis deve seguir a Seção 6 da rule** (sem hard-coding; variável de contexto agrupada em objeto; valores em `*.tfvars`).

0. **Criar o diretório `dvn-workshop-terraform/02-eks-cluster-stack/`** com os arquivos de esqueleto (`versions.tf`, `providers.tf`, `variables.tf`, `outputs.tf`), espelhando a `01`: provider `hashicorp/aws ~> 6.0`, **adicionar `hashicorp/tls`** (para o `data tls_certificate` do OIDC), Terraform `~> 1.10`, `region = var.region`, `default_tags = var.default_tags`. Adicionar já o bloco `backend "s3"` apontando para o bucket `dvn-bigode-tfstate-654654554686-us-east-1`, `key = "02-eks-cluster-stack/terraform.tfstate"`, `region = "us-east-1"`, `encrypt = true`, `use_lockfile = true` (mesmo padrão da `01`).
   *Conclusão:* `terraform init` (backend S3 + providers aws/tls) e `terraform validate` limpos na nova stack.

1. **Consumir a rede via `data "terraform_remote_state"`** apontando para o backend S3, `key = "01-networking-stack/terraform.tfstate"`. Derivar em `locals` a **lista de subnet IDs privadas** a partir do output `private_subnet_ids` (que é um **map** `nome => id`; usar `values(...)`), e o `vpc_id`. (arquivo: `eks.remote-state.tf`)
   *Conclusão:* `plan` mostra `vpc_id` e a lista de subnet IDs privadas resolvidos a partir do remote state, sem IDs hard-coded.

2. **Modelar a variável de contexto do cluster** (Seção 6 da rule): um objeto (ex.: `eks`) agrupando `name`, `version` (K8s), `authentication_mode`, `bootstrap_cluster_creator_admin_permissions` (bool), `enabled_cluster_log_types` (lista), flags de endpoint (`endpoint_private_access`, `endpoint_public_access`, `public_access_cidrs`), `log_retention_in_days`, a definição do node group (objeto com `instance_types`, `capacity_type`, `min_size`, `max_size`, `desired_size`, `max_unavailable`) e uma coleção `access_entries` (lista/map de objetos com `principal_arn` + `policy_arn` + escopo). Valores concretos em `terraform.tfvars`. Nenhum valor hard-coded nos resources. (arquivos: `variables.tf` + `terraform.tfvars`)
   *Conclusão:* `variables.tf` declara a variável com `description` e `type` objeto; `terraform.tfvars` traz os valores (K8s `1.36`, `t3.medium`, ON_DEMAND, desired 2 / min 2 / max 4, os 5 log types, `authentication_mode = "API_AND_CONFIG_MAP"`); `validate` limpo.

3. **Declarar o IAM do control plane** (`aws_iam_role` "cluster" + `aws_iam_role_policy_attachment` para `AmazonEKSClusterPolicy` e `AmazonEKSVPCResourceController`), trust em `eks.amazonaws.com` (`sts:AssumeRole` + `sts:TagSession`). (arquivo: `eks.cluster.iam.tf`)
   *Conclusão:* `plan` mostra a criação do cluster role e dos dois attachments.

4. **Declarar o log group do control plane** (`aws_cloudwatch_log_group` em `/aws/eks/<name>/cluster`, `retention_in_days` da variável), se mantido. (arquivo: `eks.logging.tf`)
   *Conclusão:* `plan` mostra o log group; ou, se omitido por decisão, o arquivo não existe e o EKS criará o log group.

5. **Declarar o `aws_eks_cluster`** (arquivo central do domínio) mapeando a variável de contexto e o remote state: `name`, `role_arn` (= cluster role), `version`, `vpc_config { subnet_ids = <subnets privadas>, endpoint_private_access, endpoint_public_access, public_access_cidrs }`, `access_config { authentication_mode, bootstrap_cluster_creator_admin_permissions }`, `enabled_cluster_log_types`, com `depends_on` nos policy attachments do passo 3 (e no log group do passo 4, se existir). (arquivo: `eks.cluster.tf`)
   *Conclusão:* `plan` mostra a criação do cluster EKS `1.36` com auth mode e os 5 log types.

6. **Declarar o IAM dos nodes** (`aws_iam_role` "node" + `aws_iam_role_policy_attachment` para `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`), trust em `ec2.amazonaws.com`. (arquivo: `eks.node-group.iam.tf`)
   *Conclusão:* `plan` mostra a criação do node role e dos três attachments.

7. **Declarar o `aws_eks_node_group`**: `cluster_name` (= cluster), `node_role_arn` (= node role), `subnet_ids` (= subnets privadas), `scaling_config { desired_size = 2, min_size = 2, max_size = 4 }`, `capacity_type = "ON_DEMAND"`, `instance_types = ["t3.medium"]`, `update_config { max_unavailable = 1 }`, com `depends_on` nos policy attachments do passo 6. (arquivo: `eks.cluster.node-group.tf`)
   *Conclusão:* `plan` mostra o node group ON_DEMAND `t3.medium` (desired 2).

8. **Declarar o OIDC provider (IRSA)**: `data "tls_certificate"` sobre o `identity[0].oidc[0].issuer` do cluster + `aws_iam_openid_connect_provider` (`url = issuer`, `client_id_list = ["sts.amazonaws.com"]`, `thumbprint_list` a partir do fingerprint). (arquivo: `eks.oidc.tf`)
   *Conclusão:* `plan` mostra o OIDC provider referenciando o issuer do cluster.

9. **Declarar as access entries (B2)**: `aws_eks_access_entry` + `aws_eks_access_policy_association` iterando (`for_each`) sobre a coleção `access_entries` da variável, cada um com `policy_arn = arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy` e `access_scope { type = "cluster" }`. Se a coleção estiver vazia, nenhum recurso é criado e o acesso vem só do `bootstrap_cluster_creator_admin_permissions` (passo 5). Sem ARN hard-coded no `.tf`. (arquivo: `eks.access-entry.tf`)
   *Conclusão:* `plan` reflete zero ou N access entries conforme os valores do `terraform.tfvars`.

10. **Expor outputs** da stack (padrão `{name}_{type}_{attribute}` da rule) a partir dos atributos dos recursos nativos: `aws_eks_cluster` (name, endpoint, arn, `certificate_authority[0].data`, `identity[0].oidc[0].issuer`, security group), `aws_iam_openid_connect_provider` (arn), cluster/node role arn, e nome/ARN do node group. (arquivo: `outputs.tf`)
   *Conclusão:* `terraform output` retorna esses valores após `apply`.

11. **`terraform plan` + revisão + `apply`** (com confirmação humana, conforme guardrails do Engineer).
   *Conclusão:* `apply` conclui; cluster `ACTIVE`; node group `ACTIVE` com 2 nodes `Ready`.

12. **Provar acesso do principal atual**: gerar kubeconfig (`aws eks update-kubeconfig --name <cluster> --region us-east-1`) e rodar `kubectl get nodes` / `kubectl auth can-i '*' '*'`.
   *Conclusão:* `kubectl get nodes` lista 2 nodes `Ready`; o principal tem permissões de admin.

13. **Validar** (ver Seção 11).
   *Conclusão:* validações da Seção 11 passam.

## 7. Layout de diretórios

A organização física dos `.tf` **deve** seguir a rule `.claude/rules/terraform-naming.md`, **Seção 5**: um recurso (ou grupo coeso) por arquivo, padrão `<dominio>.<componente>.tf`, prefixo de domínio consistente (`eks`), sufixos em kebab-case. A stack espelha a organização e as convenções da `01`. Esta árvore é o **contrato de organização de arquivos** (obrigatório); o Engineer define os nomes internos do Terraform (locals, `for_each`, etc.).

Como a decisão passou a usar **recursos nativos**, o domínio `eks` deixa de ser um único bloco de módulo e vira **vários recursos coesos**, o que permite (e exige) a quebra granular pedida. Cada arquivo concentra um recurso ou grupo coeso do mesmo propósito.

```
dvn-workshop-terraform/
├── 00-remote-backend-stack/            # existente (ADR-0002) — bucket de state
├── 01-networking-stack/                # existente (ADR-0001) — VPC/subnets (fonte do remote state)
└── 02-eks-cluster-stack/               # NOVA stack — cluster EKS (este ADR)
    ├── eks.cluster.tf                  # recurso central do domínio: aws_eks_cluster (vpc_config, access_config, enabled_cluster_log_types, version)
    ├── eks.cluster.iam.tf              # aws_iam_role (cluster role, trust eks.amazonaws.com) + policy attachments (AmazonEKSClusterPolicy, AmazonEKSVPCResourceController)
    ├── eks.cluster.node-group.tf       # aws_eks_node_group (scaling_config, capacity_type ON_DEMAND, instance_types t3.medium, update_config)
    ├── eks.node-group.iam.tf           # aws_iam_role (node role, trust ec2.amazonaws.com) + policy attachments (AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly)
    ├── eks.access-entry.tf             # aws_eks_access_entry + aws_eks_access_policy_association (for_each sobre var.eks.access_entries) — acesso do(s) principal(is)
    ├── eks.oidc.tf                     # data "tls_certificate" + aws_iam_openid_connect_provider (IRSA)
    ├── eks.logging.tf                  # aws_cloudwatch_log_group /aws/eks/<name>/cluster (opcional; retention parametrizado)
    ├── eks.remote-state.tf             # data "terraform_remote_state" da 01 + locals derivando subnets privadas/vpc_id
    ├── variables.tf                    # variável de contexto "eks" (objeto agrupado); region; default_tags
    ├── terraform.tfvars                # valores concretos (K8s 1.36, t3.medium, ON_DEMAND, desired/min/max, log types, auth mode, access_entries)
    ├── outputs.tf                      # cluster name/endpoint/arn/oidc/roles/sg (padrão {name}_{type}_{attribute})
    ├── versions.tf                     # pin Terraform (~> 1.10) + providers hashicorp/aws (~> 6.0) e hashicorp/tls + backend "s3" (key 02-eks-cluster-stack/terraform.tfstate)
    └── providers.tf                    # provider aws (region = var.region, default_tags)
```

Observações:
- **Arquivo central do domínio**: `eks.cluster.tf` (o `aws_eks_cluster`). Os demais arquivos usam o prefixo de domínio `eks` seguido do componente em kebab-case, separado por ponto — ex.: `eks.cluster.iam.tf`, `eks.cluster.node-group.tf`, `eks.node-group.iam.tf`, `eks.access-entry.tf`, `eks.oidc.tf`, `eks.logging.tf`, `eks.remote-state.tf`. Segmentos compostos (`node-group`, `access-entry`, `remote-state`) usam `-` dentro do segmento, conforme a Seção 5 da rule.
- **Um recurso (ou grupo coeso) por arquivo**: os `aws_iam_role_policy_attachment` de cada role ficam junto do seu `aws_iam_role` (grupo coeso de mesmo propósito), não em arquivo separado.
- **Nomes internos do Terraform** usam `_`, no singular, sem repetir o tipo do recurso (ex.: `aws_iam_role "cluster"` / `aws_iam_role "node"`, `aws_eks_cluster "this"` se não houver nome mais descritivo). O Engineer decide os nomes internos (locals, `for_each`, etc.).
- Se o Engineer adicionar recursos auxiliares (ex.: EKS add-ons `aws_eks_addon`, IAM roles para IRSA de cargas específicas), devem seguir o mesmo padrão `eks.<componente>.tf` (ex.: `eks.addons.tf`), mantendo o prefixo `eks`.
- `variables.tf`, `outputs.tf`, `versions.tf`/`providers.tf` permanecem convencionais na raiz da stack. O `backend "s3"` vive no `terraform {}` do `versions.tf`, como na `01`; o provider `hashicorp/tls` é declarado no `required_providers` do mesmo arquivo.

## 8. Boas práticas aplicáveis

- **Tag obrigatória de rastreabilidade**: **todo recurso AWS criado a partir deste ADR deve carregar a tag `adr=ADR-0003`.** Aplicar centralmente via `default_tags` no provider, para que cluster, node group, IAM roles, OIDC provider e log group herdem `adr=ADR-0003`. Onde um recurso aceitar `tags` próprios (ex.: `aws_eks_cluster`, `aws_eks_node_group`), não sobrescrever a chave `adr`.
- **Layout e nomenclatura**: seguir a rule `.claude/rules/terraform-naming.md`. Layout físico `<dominio>.<componente>.tf` granular (Seção 7); nomes internos com `_`, sem repetir o tipo, singular; outputs no padrão `{name}_{type}_{attribute}` com `description`.
- **Modelagem de variáveis (Seção 6 da rule)**: **sem hard-coding** nos resources; usar a **variável de contexto agrupada em objeto** (`eks`), com valores em `terraform.tfvars`. Subnets e `vpc_id` vêm do **remote state**, nunca literais. ARNs de managed policies e o ARN da cluster-access-policy podem viver como constantes de `locals`/variáveis, não espalhados inline.
- **Tagging/naming**: manter prefixo `dvn-bigode-` no nome do cluster e do node group; `default_tags = { Environment = "production", Project = "dvn-workshop-julho" }` como na `01`.
- **State**: mesma estratégia do projeto — `backend "s3"` no bucket existente, `key = "02-eks-cluster-stack/terraform.tfstate"`, `use_lockfile = true`, `encrypt = true`. **Não** recriar bucket.
- **Least privilege / IAM**:
  - Cluster role e node role escritos à mão anexando **apenas** as managed policies mínimas do EKS (cluster: `AmazonEKSClusterPolicy`, `AmazonEKSVPCResourceController`; node: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`); não anexar policies amplas.
  - `depends_on` do `aws_eks_cluster`/`aws_eks_node_group` nos respectivos `aws_iam_role_policy_attachment` (documentado nos exemplos oficiais) — sem isso o EKS não consegue deletar a infra EC2 gerenciada no destroy.
  - **IRSA** via `aws_iam_openid_connect_provider` (com `client_id_list = ["sts.amazonaws.com"]`) para que cargas futuras usem IAM por ServiceAccount em vez de credenciais no node.
  - **Access Entries** (`aws_eks_access_entry`/`aws_eks_access_policy_association`) como mecanismo primário (não `aws-auth`); `AmazonEKSClusterAdminPolicy` escopo cluster apenas para admins de workshop.
- **Segurança de rede**: nodes e control plane ENIs em **subnets privadas**; avaliar `endpoint_public_access = false` (ou `public_access_cidrs` restrito) se o acesso for de dentro da VPC.
- **Observabilidade**: control plane logging habilitado (`enabled_cluster_log_types`), incluindo `audit` e `authenticator` para rastrear acesso; `aws_cloudwatch_log_group` com `retention_in_days` explícito para não reter logs indefinidamente.
- **Versionamento de provider/Terraform**: **sem módulo comunitário**. Manter provider `hashicorp/aws ~> 6.0`, declarar `hashicorp/tls` (para o thumbprint OIDC) e Terraform `~> 1.10`. Não fazer upgrade de provider/Terraform dentro deste ADR.
- **Kubernetes version explícita**: fixar `1.36` na variável (argumento `version`; não deixar `null`/implícito) para builds reprodutíveis e para controlar upgrades conscientemente.

## 9. Riscos e mitigações

- **[NÃO VERIFICADO] ARN do principal que roda o Terraform** — o `aws sts get-caller-identity` não pôde ser executado (AWS MCP com token expirado; AWS CLI local sem credenciais: `Unable to locate credentials`). Impacto: o requisito 9 depende de conhecer o principal para B2 (access entries explícitas). **Mitigação**: usar `access_config.bootstrap_cluster_creator_admin_permissions = true` (B1), que concede admin ao criador **sem** precisar do ARN. Se o time quiser access entries explícitas, o ARN deve ser confirmado por um humano antes do apply (Premissa 3).
- **[NÃO VERIFICADO] Disponibilidade de `t3.medium` para EKS nas AZs `us-east-1a`/`us-east-1b`** — instância comum, alta probabilidade de disponibilidade, mas não confirmado via API nesta sessão (credenciais indisponíveis). **Mitigação**: se `InsufficientInstanceCapacity` numa AZ, o node group já cobre 2 AZs; alternativamente ampliar `instance_types` com um tipo equivalente.
- **[NÃO VERIFICADO] Suporte de `t3.medium` à densidade de pods desejada** — `t3.medium` (2 vCPU / 4 GiB) limita pods por node pelo modo ENI padrão do VPC CNI. Para workshop é suficiente; **mitigação**: se faltar IP/pods, considerar prefix delegation do VPC CNI ou instância maior (fora do escopo).
- **`endpoint_public_access = true`** expõe a API do cluster à internet (autenticada). **Mitigação**: restringir via `vpc_config.public_access_cidrs` ou desligar o público se o acesso for de dentro da VPC. Parametrizado.
- **`AmazonEKSClusterAdminPolicy` amplo (`system:masters`)** — **mitigação**: aceitável para workshop; para produção migrar para escopo por namespace / políticas menos amplas (novo ADR).
- **[NÃO VERIFICADO] Provider `hashicorp/tls`: docID do `data "tls_certificate"` e nomes exatos dos atributos** (`sha1_fingerprint` / `certificates[].sha1_fingerprint`, `url`) — não confirmados via MCP nesta sessão (só o padrão AWS/EKS foi verificado no provider `aws`). **Mitigação**: o Engineer deve confirmar via MCP `search_providers`/`get_provider_details` no provider `hashicorp/tls` antes de escrever o `eks.oidc.tf`. Erro no thumbprint faz o IRSA falhar silenciosamente (tokens rejeitados).
- **Composição manual (recursos nativos) aumenta a superfície de erro humano** — managed policy faltando no node role (node não entra `Ready`), `depends_on` ausente entre attachments e cluster/node group (falha no destroy), thumbprint OIDC incorreto. **Mitigação**: seguir os exemplos oficiais confirmados via MCP (Seção "Fatos verificados"); validar com `plan` + `kubectl get nodes` antes de considerar concluído.
- **Ordem de criação do `aws_cloudwatch_log_group`** — se o EKS criar o log group `/aws/eks/<name>/cluster` antes do Terraform, o `apply` pode conflitar (recurso já existe). **Mitigação**: criar o log group **antes** do cluster (`depends_on`) ou, se preferir, não gerenciá-lo no Terraform (omitir `eks.logging.tf`).
- **Custo 24/7** (control plane + 2× `t3.medium` + logs) — **mitigação**: destruir a stack ao fim do workshop; a estratégia de key-por-stack permite `destroy` isolado da `02` sem tocar rede/backend.
- **[NÃO VERIFICADO] Custo mensal exato (control plane + EC2 + CloudWatch Logs) em `us-east-1`** — não quantificado via MCP nesta sessão. **Mitigação**: confirmar na calculadora AWS antes de aprovar orçamento (ordem de dezenas de USD/mês se ficar ligado).
- **`terraform_remote_state` acopla a `02` à estrutura de outputs da `01`** — se a `01` renomear `private_subnet_ids`/`vpc_id`, a `02` quebra. **Mitigação**: os outputs da `01` são o contrato; mudanças neles exigem revisão da `02`.

## 10. Rollback

- **Passos 0–10 (código, pré-apply)**: rollback é remover/editar os arquivos; nada foi provisionado.
- **Passo 11 (apply)**: `terraform destroy` da `02-eks-cluster-stack` remove cluster, node group, IAM roles, OIDC provider, access entries e log group. Como o state tem `key` própria, o destroy é isolado e **não** afeta a `01` (rede) nem a `00` (bucket). O Terraform respeita a ordem de dependência; os `depends_on` dos policy attachments garantem que os roles só sejam removidos após o cluster/node group.
- **Reverter só o node group / sizing**: ajustar os valores no `terraform.tfvars` (ex.: `desired_size`) e reaplicar — o `aws_eks_node_group` faz update in-place / rolling (`update_config.max_unavailable`) quando possível.
- **Reverter a versão do Kubernetes**: **não há downgrade** de versão do EKS (upgrade é irreversível — AWS docs). Para "voltar", seria necessário recriar o cluster numa versão anterior (destruir + recriar). Registrar como irreversível: definir a versão com cuidado antes do apply.
- **Access entry do criador**: para remover, setar `bootstrap_cluster_creator_admin_permissions = false` no `access_config` e reaplicar (cuidado para não se auto-remover o acesso antes de garantir outra entrada admin via B2).
- **Access entries adicionais (B2)**: remover o item da coleção `access_entries` no `terraform.tfvars` e reaplicar — o `for_each` destrói apenas o `aws_eks_access_entry`/`aws_eks_access_policy_association` correspondente.

## 11. Validação

O DevOps Engineer deve comprovar ao final:

1. `terraform validate` e `terraform fmt -check` limpos na `02-eks-cluster-stack`.
2. State da `02` no bucket S3 na `key = "02-eks-cluster-stack/terraform.tfstate"`; `terraform plan` **sem mudanças** após o apply (idempotência).
3. Cluster EKS `ACTIVE` com **Kubernetes `1.36`** (`aws eks describe-cluster` / console).
4. **`authentication_mode = API_AND_CONFIG_MAP`** confirmado no cluster.
5. **Control plane logging** habilitado com os tipos `api, audit, authenticator, controllerManager, scheduler`.
6. Managed node group **ON_DEMAND**, `t3.medium`, com **2 nodes `Ready`** (`kubectl get nodes`), distribuídos nas 2 AZs privadas; `min=2`, `max=4`, `desired=2`.
7. **IAM**: cluster role (`AmazonEKSClusterPolicy`, `AmazonEKSVPCResourceController`) e node role (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`) criados **como recursos nativos**, cada um só com as managed policies mínimas; **OIDC provider (IRSA)** criado via `aws_iam_openid_connect_provider` (ARN no output; provider visível em IAM → Identity providers, apontando para o issuer do cluster).
8. **Acesso do principal atual**: `kubectl get nodes` funciona com o kubeconfig do operador; access entry do criador presente (`aws eks list-access-entries`), resultante de `bootstrap_cluster_creator_admin_permissions = true`; se houver ARNs extras (B2), seus `aws_eks_access_entry`/`aws_eks_access_policy_association` presentes com `AmazonEKSClusterAdminPolicy`.
9. Nodes e control plane ENIs em **subnets privadas** da `01` (consumidas via remote state, sem IDs hard-coded).
10. Todos os recursos com a tag `adr=ADR-0003`.
11. `terraform output` retorna cluster name/endpoint/arn/oidc/roles/security groups.

## 12. Premissas

Como o pedido foi para planejar diretamente e alguns dados não puderam ser verificados (credenciais AWS indisponíveis nesta sessão), registro as premissas — cada uma é ponto de validação humana antes/na aprovação:

1. **Região `us-east-1`** e **conta única `654654554686`** (herdadas da `01`/`00`) são o alvo do cluster. Confirmar.
2. **Ambiente**: tratado como `production` pela tag `Environment` herdada, mas o perfil é de **workshop** (custo baixo, acesso admin amplo aceitável). Confirmar se há requisito de compliance/produção real que exija endurecer IAM/endpoint.
3. **[Ponto de validação — NÃO VERIFICADO] Principal do Terraform**: `access_config.bootstrap_cluster_creator_admin_permissions = true` garante admin ao criador. Se o time quiser access entries explícitas (B2), **confirmar o(s) ARN(s)** dos principais/roles (o `aws sts get-caller-identity` não pôde ser executado nesta sessão).
4. **Kubernetes `1.36`** (a mais recente em standard support) é aceitável. Confirmar — se preferir uma versão N-1 mais "madura" (ex.: `1.35`), ajustar a variável.
5. **Node sizing**: `desired=2`, `min=2`, `max=4`, `t3.medium` ON_DEMAND. Confirmar se o dimensionamento/custo atende (control plane + 2 EC2 rodam 24/7 até destruir).
6. **Endpoint público habilitado** para conveniência de `kubectl` externo. Confirmar; se o acesso for de dentro da VPC, desligar o público ou restringir CIDRs.
7. **Logging dos 5 tipos** habilitado (custo pequeno de CloudWatch Logs). Confirmar se deseja reduzir a subconjunto (ex.: só `audit`+`authenticator`).
8. **Sem RTO/RPO, orçamento-teto ou compliance específico** informados — assume-se workshop de baixo custo. Confirmar se algum existir.

---

> **Bloqueado para implementação.** Este ADR aguarda revisão e aprovação humana.
> Para liberar a execução, edite o cabeçalho: `status: Aprovado`, preencha `aprovado_por` e `aprovado_em`, e faça commit em `docs/`.
