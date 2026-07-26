---
id: ADR-0005
titulo: Instalação do Argo CD no cluster EKS via Helm chart (helm_release) em nova stack Terraform 04-argocd-stack, e modelo GitOps com uma Application do Argo CD apontando para dvn-workshop-kubernetes/ (Kustomize) com sync automated (prune + selfHeal)
status: Aprovado
data: 2026-07-26
substitui: N/A
aprovado_por: Kenerry Serain
aprovado_em: 2026-07-26
---

# ADR-0005 — Argo CD no EKS + modelo GitOps (Application + Kustomize)

## 1. Contexto

O projeto está montando um pipeline de **Continuous Deployment (GitOps)**. O CI (ADR-0006) builda e faz push das imagens ao ECR e escreve de volta a nova tag no `dvn-workshop-kubernetes/kustomization.yaml`. Falta o componente que **observa o Git e reconcilia o cluster**: o **Argo CD**.

Estado atual **já implementado** (verificado nesta sessão):
- **Cluster EKS `dvn-bigode-eks`**, K8s `1.36` (**ADR-0003**, `Aprovado`), `authentication_mode = API_AND_CONFIG_MAP`, OIDC/IRSA provider criado, nodes em subnets privadas, `endpoint_public_access = true`. Outputs da `02` úteis aqui: `eks_cluster_name`, `eks_cluster_endpoint`, `eks_cluster_certificate_authority_data`, `eks_openid_connect_provider_arn/url`.
- **Manifests Kubernetes** em `dvn-workshop-kubernetes/` gerenciados por **Kustomize**:
  - `kustomization.yaml` raiz: `namespace: dvn-workshop`; `resources: [namespace.yaml, backend, frontend]`; bloco `images:` mapeando `dvn-workshop/production/backend` → `654654554686.dkr.ecr.us-east-1.amazonaws.com/dvn-workshop/production/backend:vN` (idem frontend). É **este bloco `images:` que o CI atualiza** (ADR-0006).
  - Componentes `backend/` e `frontend/`, cada um com `deployment.yaml` + `service.yaml` (NodePort) + `pdb.yaml` + `kustomization.yaml`, seguindo a rule `.claude/rules/kubernetes-manifests.md` (replicas ≥ 2, readiness+liveness probes, PDB, labels `app.kubernetes.io/*`).
- **Repositório GitHub** `kenerry-serain/dvn-workshop-julho` (público? privado? — ver Premissas).
- **ADR-0004** cria a federação OIDC GitHub→AWS para o CI (independente do Argo CD).

Este ADR decide: **método de instalação do Argo CD**, **namespace**, **como o Argo CD acessa o repositório Git**, e o **modelo GitOps** (Application apontando para `dvn-workshop-kubernetes/` com Kustomize; sync policy).

### Requisitos definidos pelo usuário
1. Instalar o Argo CD no cluster EKS. Decidir o método (Helm via Terraform `helm_provider`, ou manifests/ApplicationSet), o namespace e como o Argo CD acessa o repositório Git.
2. Definir o modelo GitOps: uma **Application** do Argo CD apontando para `dvn-workshop-kubernetes/` (com Kustomize), e a **sync policy** (automated vs manual, prune, selfHeal).
3. Considerar a rule `.claude/rules/kubernetes-manifests.md` onde aplicável.

### Fatos verificados via MCP / docs oficiais (2026-07-26)
- **Chart `argo-cd`**: repositório Helm `https://argoproj.github.io/argo-helm` (`helm repo add argo https://argoproj.github.io/argo-helm`). **Última versão do chart = `10.2.1`** (2026-06-09; WebSearch em artifacthub/argoproj). Community-maintained (argoproj). Instala **non-HA por default**; HA via `values`. CRDs instaladas por default. É o chart que empacota o próprio Argo CD.
- **Provider `hashicorp/helm` = `3.2.0`** (MCP). Recurso `helm_release` (docID 12457886): required `name`, `chart`; optional `repository`, `version`, `namespace`, `create_namespace`, `values` (lista de YAML raw), `set` (**block list** de `{name,value,type}` na v3.x), `wait`, `atomic`, `timeout`. Provider `helm` 3.x configura o acesso ao cluster via bloco aninhado `kubernetes = { host, cluster_ca_certificate, token/exec }`.
- **Provider `hashicorp/kubernetes` = `3.2.1`** (MCP) — para eventualmente gerenciar a `Application` CR como `kubernetes_manifest`.
- **Argo CD + Kustomize**: o Argo CD detecta Kustomize automaticamente quando há um `kustomization.yaml` no `path` da Application. A `Application` CR (`argoproj.io/v1alpha1`) referencia `spec.source { repoURL, path, targetRevision }` e `spec.syncPolicy.automated { prune, selfHeal }`. (Versão exata do `apiVersion` a confirmar via `list_api_versions` no cluster — ver Riscos.)

### Conflitos / divergências detectados
1. **Nenhum ADR anterior contradiz este pedido.** Depende da `02` (cluster). Não substitui nada.
2. A rule `.claude/rules/kubernetes-manifests.md` governa os **manifests de workload** (Deployment/Service/PDB dos apps) — já atendida pelos manifests existentes. O **Argo CD em si** é instalado por Helm chart de terceiros; a rule não se aplica ao chart, mas **se aplica a qualquer manifesto de workload que este ADR criar** (nenhum, além da `Application` CR, que não é um Deployment de app).

## 2. Drivers da decisão

1. **GitOps declarativo e reprodutível**: o cluster deve convergir para o que está no Git; o Argo CD é a fonte de reconciliação. A instalação também deve ser IaC (não `kubectl apply` manual).
2. **Consistência com o projeto**: infra em Terraform, stacks numeradas, backend S3 por stack, tag `adr=`. O Argo CD deve entrar como stack numerada (`04-...`) consumindo a `02` via remote state.
3. **Simplicidade operacional para workshop**: menos partes móveis; instalação repetível com um `terraform apply`; sync automático para o deploy "acontecer sozinho" quando o CI commita a nova tag.
4. **Segurança**: acesso do Argo CD ao Git com o mínimo necessário (repo público → sem credencial; repo privado → deploy key/token read-only); Argo CD server não exposto publicamente sem necessidade.
5. **Baixo acoplamento CI↔CD**: o CI (ADR-0006) **não** fala com o cluster; ele só commita no Git. O Argo CD detecta o commit e sincroniza. Isso mantém as responsabilidades separadas.

## 3. Opções consideradas

### Dimensão A — Método de instalação do Argo CD

#### A1 — Helm chart `argo-cd` via Terraform `helm_release` em nova stack `04-argocd-stack` — **escolhida**
Uma stack Terraform dedicada usa o provider `helm` (3.x) para instalar o chart `argo-cd` (`10.2.1`, pinado) no cluster, consumindo os dados de conexão do cluster (endpoint, CA, auth) da `02` via `terraform_remote_state` + `data "aws_eks_cluster_auth"` (ou `exec` com AWS CLI).

Trade-offs:
- **IaC end-to-end**: instalação versionada, repetível, com `values` explícitos; upgrade do Argo CD é bump de `version` + `apply`.
- **Consistência**: stack numerada, mesmo backend/tag/naming.
- **Custo operacional**: exige configurar o provider `helm`/`kubernetes` com auth do EKS (host + CA + token). Padrão bem documentado.
- **Acoplamento**: depende dos outputs da `02` (endpoint/CA) — contrato explícito.

#### A2 — `kubectl apply` dos manifests oficiais de install do Argo CD (não-Helm) — **descartada**
Aplicar o `install.yaml` do Argo CD manualmente ou via `kubernetes_manifest`.

Trade-offs:
- **Sem dependência do chart**, mas **fora do padrão IaC do projeto** se feito por `kubectl` manual; via `kubernetes_manifest` seriam dezenas de recursos individuais para gerenciar, com upgrades trabalhosos. **Descartada** por pior ergonomia de upgrade e maior superfície de manutenção que o chart.

#### A3 — Instalar o Argo CD e já usar **ApplicationSet** para os apps — **descartada (por ora)**
Usar ApplicationSet para gerar Applications automaticamente.

Trade-offs:
- **Poderoso** para muitos apps/clusters/ambientes, mas **overkill** para dois componentes (backend/frontend) num único diretório Kustomize e um único cluster. Adiciona complexidade sem benefício no escopo do workshop. **Descartada por ora**; registrada como evolução futura (novo ADR) se surgirem múltiplos ambientes.

### Dimensão B — Modelo GitOps (como o Argo CD gerencia os apps)

#### B1 — **Uma única Application** apontando para `dvn-workshop-kubernetes/` (Kustomize da raiz) — **escolhida**
Uma `Application` (`argoproj.io/v1alpha1`) com `source.repoURL = https://github.com/kenerry-serain/dvn-workshop-julho`, `source.path = dvn-workshop-kubernetes`, `source.targetRevision = main`, `destination` = o próprio cluster (`https://kubernetes.default.svc`) + `namespace: dvn-workshop`. O Argo CD aplica o `kustomization.yaml` raiz, que já traz namespace + backend + frontend + o bloco `images:`.

Trade-offs:
- **Simplicidade**: um objeto para o sistema inteiro; casa perfeitamente com o layout Kustomize existente (raiz agrega backend/frontend).
- **Atomicidade**: um commit de tag no `kustomization.yaml` dispara a reconciliação de tudo o que mudou.
- **Limitação**: backend e frontend sincronizam sob a mesma Application (mesma sync policy). Aceitável — eles já vivem no mesmo Kustomize raiz e mesmo namespace.

#### B2 — **App-of-apps** (uma Application raiz que cria Applications filhas para backend e frontend) — **descartada (por ora)**
Uma Application "pai" versiona Applications filhas separadas.

Trade-offs:
- **Granularidade** (sync/rollback por app) e escalabilidade, mas **exige criar manifests de Application filhas** e mais um nível de indireção. Para dois componentes coesos num só Kustomize é complexidade desnecessária. **Descartada por ora**; caminho de evolução se o número de apps crescer.

### Dimensão C — Sync policy

#### C1 — `automated` com `prune: true` e `selfHeal: true` — **escolhida**
O deploy "acontece sozinho": quando o CI commita a nova tag no `kustomization.yaml`, o Argo CD detecta e sincroniza. `prune` remove recursos que saíram do Git; `selfHeal` reverte drift feito à mão no cluster.

Trade-offs:
- **Fecha o loop de CD** sem passo manual (objetivo do requisito).
- **`prune`**: remove do cluster o que for removido do Git — comportamento correto de GitOps, mas exige disciplina (um `git revert` remove workloads). Aceito.
- **`selfHeal`**: impede "conserto na unha" persistir — desejável para consistência; pode surpreender quem edita o cluster manualmente. Aceito para workshop.

#### C2 — `manual` (sync disparado por humano no UI/CLI) — **descartada como padrão**
Trade-offs: mais controle/gate humano, mas **quebra o CD automático** que o pipeline visa. Fica registrada como opção se o time quiser um portão de aprovação de deploy (ex.: produção real); então usar `automated` só em dev e `manual` em prod (novo ADR).

## 4. Decisão

**A1 + B1 + C1.**

1. **Instalar o Argo CD via Helm** numa nova stack **`04-argocd-stack`** (Terraform), usando `helm_release`:
   - `chart = "argo-cd"`, `repository = "https://argoproj.github.io/argo-helm"`, `version = "10.2.1"` (pinado; parametrizado);
   - `namespace = "argocd"`, `create_namespace = true`;
   - `values` para: instalar **non-HA** (workshop), Argo CD server **sem exposição pública por padrão** (`service.type: ClusterIP`; acesso via `kubectl port-forward` ou, se o time quiser, um LoadBalancer/Ingress em ADR futuro), e retenção de defaults sensatos. `values` parametrizado.
   - Provider `helm` 3.x configurado com bloco `kubernetes = { host, cluster_ca_certificate, token/exec }`, onde `host` e `cluster_ca_certificate` vêm dos outputs da `02` via `terraform_remote_state`, e a autenticação usa `data "aws_eks_cluster_auth"` (token) **ou** `exec` com `aws eks get-token` (preferir `exec` para token não persistir no state — ver Riscos).

2. **Modelo GitOps — uma única `Application`** (`argoproj.io/v1alpha1`), criada de forma declarativa. Duas sub-opções de materialização (o Engineer escolhe o "como"; ambas aceitáveis):
   - (a) como recurso `kubernetes_manifest` na mesma stack `04-argocd-stack` (provider `kubernetes` 3.x), **com `depends_on` no `helm_release`** (as CRDs do Argo CD precisam existir antes); **ou**
   - (b) como um manifesto YAML versionado no repositório (ex.: `dvn-workshop-kubernetes/argocd/application.yaml`) aplicado uma única vez (bootstrap) — porém, para manter tudo em Terraform, **preferir (a)**.
   - `spec.source`: `repoURL = https://github.com/kenerry-serain/dvn-workshop-julho`, `path = dvn-workshop-kubernetes`, `targetRevision = main` (parametrizado).
   - `spec.destination`: `server = https://kubernetes.default.svc`, `namespace = dvn-workshop`.
   - `spec.syncPolicy.automated { prune = true, selfHeal = true }`; `syncOptions: [CreateNamespace=false]` (o namespace `dvn-workshop` já é criado pelo próprio `namespace.yaml` do Kustomize).

3. **Acesso do Argo CD ao Git**:
   - **Se o repositório for público**: nenhuma credencial — o Argo CD clona anonimamente. **Preferido para workshop.**
   - **Se for privado**: registrar um **repository credential** read-only (deploy key SSH ou PAT/GitHub App token com escopo mínimo de leitura do repo), via `values`/secret do Argo CD. Modelado como variável sensível, **não** commitada; valor injetado no apply. Ver Premissas/Riscos.

Justificativa frente aos drivers:
- **Driver 1**: Argo CD reconcilia o cluster com o Git; instalação e Application são IaC.
- **Driver 2**: stack `04-argocd-stack`, backend S3 por stack, tag `adr=ADR-0005`, consumo da `02` via remote state.
- **Driver 3**: um `helm_release` + uma Application; sync automático fecha o loop.
- **Driver 4**: server ClusterIP (sem exposição pública por default); credencial de Git só se o repo for privado, read-only.
- **Driver 5**: o Argo CD (dentro do cluster) puxa do Git; o CI não toca o cluster.

## 5. Consequências

Positivas:
- CD declarativo: o commit de tag no `kustomization.yaml` (ADR-0006) dispara deploy automático via Argo CD.
- Instalação e Application versionadas em Terraform; upgrade do Argo CD = bump de `version` + `apply`.
- `selfHeal` + `prune` garantem que o cluster reflita o Git (elimina drift).
- Separação limpa CI↔CD: o CI só commita; o Argo CD só reconcilia.

Negativas / dívida técnica aceita:
- **Non-HA** (workshop): um único replica do repo-server/application-controller; se cair, sync pausa até reiniciar. Aceito; produção usaria `values` HA (novo ADR).
- **`prune`/`selfHeal`**: mudanças manuais no cluster são revertidas; remoção no Git remove no cluster. Exige disciplina de Git. Aceito.
- **`data "aws_eks_cluster_auth"` no state**: se usado, o token do EKS pode ir para o state (sensível). **Mitigação**: preferir `exec` (`aws eks get-token`) no provider; ver Riscos.
- **Custo**: pods do Argo CD consomem recursos do node group (2× t3.medium). Pequeno; monitorar capacidade.
- **Argo CD server ClusterIP**: acesso ao UI exige `port-forward` — menos conveniente, mais seguro. Aceito.
- **Acoplamento à conexão do cluster (outputs da `02`)**: mudança na `02` pode quebrar a auth do provider `helm`.

## 6. Plano de implementação

Passos atômicos, ordenados por dependência. Modelagem de variáveis e layout seguem a rule `.claude/rules/terraform-naming.md` (Seções 5 e 6).

0. **Criar `dvn-workshop-terraform/04-argocd-stack/`** (esqueleto espelhando a `02`/`03`): `versions.tf` (Terraform `~> 1.10`; providers `hashicorp/aws ~> 6.0`, `hashicorp/helm ~> 3.2`, `hashicorp/kubernetes ~> 3.2`; backend `s3` `key = "04-argocd-stack/terraform.tfstate"`, `encrypt`, `use_lockfile`), `providers.tf`, `variables.tf`, `outputs.tf`. `default_tags` com `adr = "ADR-0005"`.
   *Conclusão:* `terraform init` (aws/helm/kubernetes + backend) e `validate` limpos.

1. **Consumir a `02` via `data "terraform_remote_state"`** e derivar `eks_cluster_name`, `eks_cluster_endpoint`, `eks_cluster_certificate_authority_data`. Configurar o provider `helm` (bloco `kubernetes = {...}`) e o provider `kubernetes` com esses valores + auth (`exec` `aws eks get-token`, preferido; ou `data "aws_eks_cluster_auth"`). (arquivos: `argocd.remote-state.tf`, `providers.tf`)
   *Conclusão:* `plan` autentica no cluster (providers resolvem host/CA/token sem erro).

2. **Modelar a variável de contexto** (Seção 6): objeto (ex.: `argocd`) com `chart_version`, `namespace`, `values` (ou flags → `set`), `application { repo_url, path, target_revision, dest_namespace, automated_prune, automated_self_heal }`, e `git_repo { private (bool), credential_secret_ref }`. Valores em `terraform.tfvars`; segredos de Git **não** em `.tfvars` versionado (usar `-var`/env/secret manager). (arquivos: `variables.tf`, `terraform.tfvars`)
   *Conclusão:* `validate` limpo; nenhum literal nos resources.

3. **Instalar o Argo CD** (`helm_release` `argo-cd` `10.2.1`, `namespace = "argocd"`, `create_namespace = true`, `values` non-HA + server ClusterIP, `wait = true`). (arquivo: `argocd.tf`)
   *Conclusão:* `apply` cria o release; pods do Argo CD `Running` no namespace `argocd`; CRDs `applications.argoproj.io` presentes.

4. **(Se repo privado) Registrar a credencial de Git** do Argo CD (secret de repository read-only), via `values`/`kubernetes_manifest`, sem commitar o segredo. (arquivo: `argocd.repo-credential.tf` — só existe se privado)
   *Conclusão:* Argo CD lista o repositório como conectado (Settings → Repositories) sem erro de auth.

5. **Confirmar o `apiVersion` da Application** no cluster via `list_api_versions` (`applications.argoproj.io`), depois **declarar a `Application`** (`kubernetes_manifest`, `depends_on = [helm_release.argo_cd]`): `source { repoURL, path = "dvn-workshop-kubernetes", targetRevision = "main" }`, `destination { server = "https://kubernetes.default.svc", namespace = "dvn-workshop" }`, `syncPolicy.automated { prune, selfHeal }`. (arquivo: `argocd.application.tf`)
   *Conclusão:* `plan`/`apply` criam a Application; `apiVersion` confirmado pelo cluster.

6. **Expor outputs** (`argocd_namespace`, `argocd_server_service`, `argocd_application_name`). (arquivo: `outputs.tf`)
   *Conclusão:* `terraform output` retorna os valores.

7. **`plan` + revisão + `apply`** (confirmação humana).
   *Conclusão:* Argo CD instalado; Application `Synced`/`Healthy` (após primeira reconciliação, com as imagens do ECR).

8. **Validar** (Seção 11).

## 7. Layout de diretórios

Segue a rule `.claude/rules/terraform-naming.md`, Seção 5 (prefixo de domínio `argocd`). Contrato de organização (obrigatório).

```
dvn-workshop-terraform/
├── 02-eks-cluster-stack/             # existente (ADR-0003) — cluster + ECR (remote state consumido)
├── 03-cicd-oidc-stack/               # ADR-0004 — OIDC GitHub->AWS
└── 04-argocd-stack/                  # NOVA stack — Argo CD + Application (este ADR)
    ├── argocd.tf                     # helm_release "argo-cd" (recurso central do domínio)
    ├── argocd.application.tf         # kubernetes_manifest da Application (argoproj.io/v1alpha1), depends_on helm_release
    ├── argocd.repo-credential.tf     # (condicional) secret de repository read-only, só se o repo for privado
    ├── argocd.remote-state.tf        # data terraform_remote_state da 02 + locals (endpoint/CA/name)
    ├── variables.tf                  # variável de contexto "argocd" + region + default_tags
    ├── terraform.tfvars              # valores (chart_version 10.2.1, namespace, application {...}, flags de sync)
    ├── outputs.tf                    # argocd_namespace, argocd_application_name, ...
    ├── versions.tf                   # Terraform ~> 1.10 + aws ~> 6.0 + helm ~> 3.2 + kubernetes ~> 3.2 + backend s3 (key 04-argocd-stack/...)
    └── providers.tf                  # provider aws + helm (kubernetes = {...}) + kubernetes (auth via exec aws eks get-token)
```

Observações:
- **Arquivo central**: `argocd.tf` (o `helm_release`). Demais arquivos usam o prefixo `argocd` + componente em kebab-case.
- A `Application` CR **não é** um Deployment de app, então a rule `.claude/rules/kubernetes-manifests.md` (probes/PDB/replicas) **não se aplica** a ela; aplica-se aos manifests de workload em `dvn-workshop-kubernetes/` (já conformes).
- Nomes internos com `_`, singular (ex.: `helm_release "argo_cd"`).

## 8. Boas práticas aplicáveis

- **Tag obrigatória de rastreabilidade**: **todo recurso AWS desta stack deve carregar `adr = "ADR-0005"`** via `default_tags`. (O `helm_release`/`kubernetes_manifest` criam objetos Kubernetes, não recursos AWS taggáveis; onde houver recurso AWS — ex.: se um LoadBalancer for criado por um Service futuro — a tag deve constar. Para os objetos K8s, aplicar o label `app.kubernetes.io/managed-by` e, se desejado, uma anotação/label rastreando o ADR.)
- **GitOps**: Application declarativa, `syncPolicy.automated { prune, selfHeal }` para fechar o loop; `targetRevision` fixo (`main`) para builds reprodutíveis.
- **Segurança**:
  - Argo CD server **sem exposição pública** por default (`ClusterIP`); acesso via `port-forward`. Trocar a senha admin inicial e/ou desabilitar o usuário admin após configurar SSO/RBAC (evolução futura).
  - Acesso ao Git com **mínimo privilégio**: repo público → sem credencial; privado → deploy key/token **read-only**, nunca write. Segredo **não** versionado.
  - Preferir `exec` (`aws eks get-token`) na config dos providers `helm`/`kubernetes` para **não** persistir token do EKS no state.
- **Versionamento**: `chart_version` **pinado** (`10.2.1`); upgrade consciente via bump + `apply`. Providers `helm ~> 3.2`, `kubernetes ~> 3.2`, `aws ~> 6.0`, Terraform `~> 1.10`.
- **State**: `backend "s3"` no bucket existente, `key = "04-argocd-stack/terraform.tfstate"`, `encrypt`, `use_lockfile`.
- **Modelagem de variáveis (Seção 6 da rule)**: objeto de contexto `argocd`; conexão do cluster vinda do remote state da `02`, sem hard-coding de endpoint/CA.
- **Idempotência**: `helm_release` com `wait = true`; a Application converge por reconciliação — `plan` deve ficar limpo após o apply.

## 9. Riscos e mitigações

- **[NÃO VERIFICADO] `apiVersion` exato da `Application`/`ApplicationSet`** no cluster (ex.: `argoproj.io/v1alpha1`) — não consultado via `list_api_versions` nesta sessão (sem acesso ao cluster). **Mitigação**: o Engineer roda `list_api_versions` após instalar o chart e antes de declarar a Application; declarar `kubernetes_manifest` só após as CRDs existirem (`depends_on` no `helm_release`).
- **CRDs do Argo CD vs. `kubernetes_manifest`**: o provider `kubernetes` valida o manifesto contra o schema da CRD **no plan**; se a CRD ainda não existir, o `plan` da Application falha. **Mitigação**: `depends_on` + aplicar em duas fases (chart primeiro) ou usar `-target` no primeiro apply; alternativamente materializar a Application via `values` do próprio chart (`server.additionalApplications`/`extraObjects`) se disponível na versão do chart.
- **[NÃO VERIFICADO] Repositório público vs. privado** (`kenerry-serain/dvn-workshop-julho`) — define se é preciso credencial de Git no Argo CD. **Mitigação**: confirmar antes do apply; se privado, provisionar deploy key/token read-only (Premissa 2).
- **Token do EKS no state** (se usar `data "aws_eks_cluster_auth"`) — **mitigação**: usar `exec` (`aws eks get-token`); o exec plugin resolve o token em runtime, sem persistir.
- **`endpoint_public_access = true` na `02`** facilita a auth do provider `helm` de fora da VPC (do runner do apply). Se o time desligar o endpoint público (recomendado em prod), o `apply` desta stack precisa rodar **de dentro da VPC** (self-hosted runner/bastion). **Mitigação**: registrar essa dependência; alinhar com o ADR-0003.
- **`selfHeal` + `prune` inesperados**: um `git revert` remove workloads; edições manuais somem. **Mitigação**: documentar o contrato GitOps ao time; `prune` pode ser desligado inicialmente se quiserem observar antes.
- **Capacidade do node group**: pods do Argo CD + apps competindo por 2× t3.medium. **Mitigação**: monitorar; a `02` permite `max_size = 4` para escalar manualmente.
- **Chart community-maintained**: mudanças de schema de `values` entre versões. **Mitigação**: `version` pinado; revisar changelog no upgrade.

## 10. Rollback

- **Passos 0–6 (código, pré-apply)**: remover/editar arquivos; nada provisionado.
- **Desinstalar o Argo CD**: `terraform destroy` da `04-argocd-stack` remove a Application e o `helm_release` (que desinstala o chart e, conforme `values`, as CRDs). State isolado (`key` própria) → não afeta `02`/`03`. **Atenção**: remover a Application com `prune` ativo pode **remover os workloads dos apps** que ela gerencia; para preservar os apps, remover a Application com política que **não** faz cascade prune, ou destruir apenas o `helm_release` mantendo os Deployments.
- **Reverter só a sync policy**: alterar `automated`/`prune`/`selfHeal` no `terraform.tfvars` e reaplicar (update da Application).
- **Reverter versão do chart**: ajustar `chart_version` e reaplicar (o `helm_release` faz upgrade/downgrade — atenção a migrações de CRD, que podem não ser reversíveis; tratar downgrade de CRD como potencialmente irreversível).
- **Desconectar o Git**: remover o repository credential (se privado) e reaplicar.

## 11. Validação

O Engineer deve comprovar ao final:
1. `terraform validate` e `fmt -check` limpos na `04-argocd-stack`; state no S3 (`key = "04-argocd-stack/..."`); `plan` sem mudanças após o apply.
2. `helm_release` `argo-cd` versão `10.2.1` no namespace `argocd`; pods do Argo CD `Running` (`kubectl get pods -n argocd`).
3. CRD `applications.argoproj.io` presente; `apiVersion` da Application confirmado via `list_api_versions`.
4. **Application** criada, `source.path = dvn-workshop-kubernetes`, `targetRevision = main`, `syncPolicy.automated { prune, selfHeal }`; estado **`Synced`** e **`Healthy`** (`kubectl get applications -n argocd`).
5. No namespace `dvn-workshop`: Deployments `backend` e `frontend` criados pelo Argo CD, com as imagens do ECR (`654654554686.dkr.ecr.us-east-1.amazonaws.com/dvn-workshop/production/{backend,frontend}:vN`), Pods `Ready`, Services NodePort e PDBs presentes (conforme os manifests existentes).
6. **Teste de reconciliação**: um commit que muda a tag no `kustomization.yaml` (simulando o write-back do ADR-0006) faz o Argo CD sincronizar automaticamente e atualizar os Deployments, **sem** intervenção manual.
7. **Teste de selfHeal**: uma edição manual (ex.: `kubectl scale`) é revertida pelo Argo CD para o estado do Git.
8. Argo CD server **não** exposto publicamente (`service.type = ClusterIP`); acesso via `port-forward`.
9. (Se privado) repositório conectado no Argo CD com credencial read-only; (se público) sem credencial.

## 12. Premissas

Como o pedido foi para planejar diretamente e alguns dados não puderam ser verificados (sem acesso ao cluster/credenciais nesta sessão):

1. **Cluster `dvn-bigode-eks` ACTIVE** e acessível pelo runner do `apply` (endpoint público habilitado na `02`). Confirmar; se o endpoint for privado, o apply roda de dentro da VPC.
2. **[Ponto de validação] Visibilidade do repositório** `kenerry-serain/dvn-workshop-julho` (público vs. privado). Se privado, provisionar deploy key/token **read-only** para o Argo CD (segredo não versionado). Confirmar.
3. **Deploy automático desejado** (`syncPolicy.automated`, prune + selfHeal). Confirmar; se o time quiser gate manual em produção, usar `manual` (novo ADR/ambiente).
4. **Argo CD non-HA e server ClusterIP** (workshop). Confirmar; produção usaria HA e acesso via Ingress/SSO.
5. **`targetRevision = main`** é a branch de deploy. Confirmar (casa com o write-back do ADR-0006).
6. **Sem requisito de multi-cluster/multi-ambiente** agora — por isso uma Application única (não ApplicationSet/app-of-apps). Confirmar.

---

> **Bloqueado para implementação.** Este ADR aguarda revisão e aprovação humana.
> Para liberar a execução, edite o cabeçalho: `status: Aprovado`, preencha `aprovado_por` e `aprovado_em`, e faça commit em `docs/`.
