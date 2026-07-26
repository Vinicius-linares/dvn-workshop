---
id: ADR-0004
titulo: Autenticação federada OIDC do GitHub Actions para a AWS (sem access keys de longa duração) via IAM OpenID Connect provider e IAM Role assumível por Web Identity, em nova stack 03-cicd-oidc-stack, com trust policy restrita ao repositório e permissões mínimas de push no ECR
status: Aprovado
data: 2026-07-26
substitui: N/A
aprovado_por: Kenerry Serain
aprovado_em: 2026-07-26
---

# ADR-0004 — Autenticação OIDC GitHub Actions → AWS (stack `03-cicd-oidc-stack`)

## 1. Contexto

O projeto `dvn-workshop-julho` está implementando um pipeline de **Continuous Deployment (GitOps)** para as aplicações frontend (Next.js) e backend (ASP.NET). Estado atual **já implementado** (verificado nesta sessão lendo os arquivos e ADRs em `docs/`):

- **`00-remote-backend-stack`** — bucket S3 de state remoto `dvn-bigode-tfstate-654654554686-us-east-1` (**ADR-0002**, `status: Aprovado`). **Conta AWS `654654554686`**, região `us-east-1`.
- **`01-networking-stack`** — VPC `10.0.0.0/24` (**ADR-0001**, `status: Aprovado`), state no S3.
- **`02-eks-cluster-stack`** — cluster EKS `dvn-bigode-eks`, K8s `1.36`, recursos nativos (**ADR-0003**, `status: Aprovado`, Kenerry Serain, 2026-07-26). **Esta stack também cria os repositórios ECR** (`ecr.tf`, `var.ecr_repositories`): `dvn-workshop/production/backend` e `dvn-workshop/production/frontend`, e os expõe nos outputs `ecr_repository_urls` (map `name => url`) e `ecr_repository_arns` (map `name => arn`). Também cria um `aws_iam_openid_connect_provider` **para o EKS/IRSA** (issuer do próprio cluster) — recurso distinto do provider do GitHub tratado aqui.
- **Repositório GitHub**: `kenerry-serain/dvn-workshop-julho` (verificado em `git remote -v`).
- **Imagens já publicadas** no ECR (repos existentes). Manifests Kubernetes em `dvn-workshop-kubernetes/` (Kustomize) já consomem as imagens do ECR.

Para o CI (build + push das imagens) rodar no GitHub Actions **sem armazenar `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` de longa duração** como secrets, é preciso estabelecer **federação de identidade OIDC** entre o GitHub Actions e a AWS: um **IAM OIDC identity provider** para `token.actions.githubusercontent.com` e uma **IAM Role** assumível via `sts:AssumeRoleWithWebIdentity`, com trust policy restrita ao repositório e permissões mínimas de push no ECR.

Este ADR decide **onde** esses recursos IAM vivem em Terraform e **como** são modelados. Os workflows que consomem essa role — incluindo a estratégia de tag por SHA e o write-back GitOps — são objeto do **ADR-0006** (pipeline de CI de ponta a ponta); o modelo GitOps/ArgoCD é o **ADR-0005**.

### Requisitos definidos pelo usuário
1. IAM OIDC identity provider para `token.actions.githubusercontent.com`.
2. IAM Role assumível via web identity federation, com **trust policy restrita ao repositório** (`condition` sobre `sub`/`aud`).
3. **Permissões mínimas de ECR** (login + push): `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage`.
4. Decidir **onde** isso vive em Terraform (nova stack numerada vs. parte de outra), seguindo o padrão de stacks numeradas e a nomenclatura do projeto.

### Fatos verificados via MCP / docs oficiais (2026-07-26)
- **OIDC provider do GitHub**: `url = https://token.actions.githubusercontent.com`, `client_id_list` (audience) `= ["sts.amazonaws.com"]` (AWS docs — *Use IAM roles to connect GitHub Actions to actions in AWS*; *Create a role for OpenID Connect federation*).
- **Trust policy** (AWS docs, *IAM condition context keys — Using GitHub* e KB de troubleshooting AssumeRoleWithWebIdentity): `Action = sts:AssumeRoleWithWebIdentity`, `Principal.Federated =` ARN do oidc-provider, `Condition`:
  - `StringEquals` → `token.actions.githubusercontent.com:aud = "sts.amazonaws.com"`;
  - `StringLike` (ou `StringEquals`) → `token.actions.githubusercontent.com:sub = "repo:kenerry-serain/dvn-workshop-julho:*"` (ou um `:sub` mais específico por branch/environment).
  - A AWS **exige** que a condition `:sub` **não** seja apenas wildcard/null — sem restrição de repo, qualquer repositório GitHub poderia assumir a role.
- **Thumbprint**: doc oficial do recurso `aws_iam_openid_connect_provider` (hashicorp/aws `6.56.0`, docID 12942122, MCP): para IdPs conhecidos (**GitHub**, GitLab, Google, Auth0, JWKS em S3) **a AWS valida o TLS do JWKS contra sua própria library de CAs confiáveis** e **qualquer `thumbprint_list` configurado é retido mas não usado** para verificação. O recurso pode ser criado **sem** `thumbprint_list` (exemplo oficial "Without A Thumbprint"). Portanto o thumbprint deixou de ser obrigatório/carregado para o GitHub.
- **Recurso `aws_iam_openid_connect_provider`** (docID 12942122): args `url` (obrigatório), `client_id_list` (obrigatório), `thumbprint_list` (**opcional**), `tags`. Exporta `arn`.
- **Recursos IAM da role**: `aws_iam_role` (com `assume_role_policy` de `sts:AssumeRoleWithWebIdentity`) + `aws_iam_policy` + `aws_iam_role_policy_attachment` (ou `aws_iam_role_policy` inline). O documento de trust é montável com `data "aws_iam_policy_document"` (com bloco `principals { type = "Federated" }` e `condition`). Nomes exatos desses recursos IAM não reconfirmados individualmente nesta sessão além do padrão já usado na `02` (que usa `aws_iam_role`/`aws_iam_role_policy_attachment`); registrado nos Riscos como item a confirmar pelo Engineer.

### Conflitos / divergências detectados com o contexto obrigatório
1. **Nenhum ADR anterior contradiz este pedido.** ADR-0001/0002/0003 estão `Aprovado`; este ADR **não substitui** nenhum — **depende** do ECR criado na `02` (ADR-0003) para escopar as permissões por ARN de repositório.
2. **Divergência de nomes de repositório ECR (a resolver antes do apply):** o arquivo `dvn-workshop-apps/ecr-apps.json` cita repositórios `devops-na-nuvem/prod/backend` e `devops-na-nuvem/prod/frontend`, **mas** os repositórios ECR realmente criados na `02` (e usados no `dvn-workshop-kubernetes/kustomization.yaml`) são `dvn-workshop/production/backend` e `dvn-workshop/production/frontend`. Este ADR adota como **fonte da verdade os repositórios reais da `02`** (`dvn-workshop/production/*`). Registrado nos Riscos: o `ecr-apps.json` está desatualizado e deve ser corrigido (ou ignorado) para os workflows do ADR-0006 apontarem ao repo certo.
3. **Dois OIDC providers distintos na conta:** a `02` já cria um `aws_iam_openid_connect_provider` para o **EKS/IRSA** (issuer do cluster). Este ADR cria **outro**, para o **GitHub** (`token.actions.githubusercontent.com`). São recursos independentes com `url` diferente — não há conflito, mas é preciso não confundi-los.

## 2. Drivers da decisão

1. **Segurança — eliminar credenciais de longa duração** (requisito central): nenhuma access key estática em secrets do GitHub. Somente credenciais efêmeras via STS/OIDC.
2. **Least privilege**: a role concede **apenas** o mínimo para login + push no ECR, escopado aos **ARNs dos dois repositórios** da `02`, e é assumível **somente** pelo repositório GitHub deste projeto.
3. **Isolamento de blast radius do state**: recursos IAM globais de CI/CD não devem compartilhar state com a rede (`01`) nem com o cluster (`02`), para que um `destroy` da stack de EKS não toque o IAM de CI e vice-versa.
4. **Consistência com as convenções do projeto**: stacks numeradas (`NN-<nome>-stack`), backend S3 com `key` por stack, pins de provider/Terraform, naming `dvn-bigode-`, modelagem de variáveis por objeto de contexto (rule `.claude/rules/terraform-naming.md`), tag `adr=`.
5. **Baixo acoplamento e reprodutibilidade**: consumir o ARN dos repositórios ECR da `02` via `terraform_remote_state`, sem hard-coding de ARNs.

## 3. Opções consideradas

### Dimensão A — Onde os recursos IAM de CI/CD vivem

#### A1 — Nova stack `03-cicd-oidc-stack` — **escolhida**
Criar uma nova stack numerada dedicada ao IAM de CI/CD (OIDC provider do GitHub + role + policy), consumindo os outputs da `02` (ARNs dos repos ECR) via `terraform_remote_state`.

Trade-offs:
- **Isolamento**: state próprio (`key = "03-cicd-oidc-stack/terraform.tfstate"`); `destroy` do EKS não afeta o IAM de CI, e recriar o cluster não recria a federação OIDC.
- **Consistência**: segue exatamente o padrão `NN-<nome>-stack` já estabelecido (00/01/02).
- **Custo operacional**: uma stack a mais para `init`/`apply` — trivial; são poucos recursos IAM.
- **Acoplamento**: depende dos outputs da `02` (ARNs ECR) via remote state — contrato explícito e auditável.

#### A2 — Colocar os recursos dentro da `02-eks-cluster-stack` — **descartada**
Adicionar o OIDC provider do GitHub + role no mesmo diretório da `02`.

Trade-offs:
- **Menos stacks**: um `apply` a menos.
- **Blast radius ruim**: o IAM de CI passa a compartilhar ciclo de vida e state com o cluster. Um `terraform destroy` da `02` (esperado ao fim de um workshop, conforme ADR-0003) **removeria a federação OIDC** junto — indesejado, pois a federação é infra transversal de CI. Mistura responsabilidades (cluster vs. identidade de pipeline).
- **Descartada** por violar o driver 3 (isolamento de blast radius) e a coesão de stacks.

#### A3 — Criar o OIDC provider/role fora do Terraform (console/CLI manual) — **descartada**
Criar via `aws iam create-open-id-connect-provider` / console.

Trade-offs:
- **Rapidez inicial**, porém **sem IaC**: drift, sem rastreabilidade, sem tag `adr=`, contraria todo o padrão do projeto (tudo em Terraform, state versionado). **Descartada.**

### Dimensão B — Thumbprint do OIDC provider

#### B1 — Criar o provider **sem `thumbprint_list`** (confiar na validação por CA da AWS) — **escolhida**
Verificado (docID 12942122): para o GitHub a AWS valida o JWKS via sua library de CAs; `thumbprint_list` é retido mas **não usado**. Omitir evita carregar um valor frágil (o thumbprint do GitHub já mudou historicamente e quebrou pipelines).

Trade-offs:
- **Menos manutenção / menos frágil**: nada de thumbprint desatualizado quebrando `AssumeRoleWithWebIdentity`.
- **Alinhado à orientação atual da AWS**.

#### B2 — Fornecer `thumbprint_list` explícito (thumbprint do GitHub) — **descartada como padrão**
Passar o fingerprint (ex.: derivado via `data "tls_certificate"` sobre o JWKS, como a `02` faz para o EKS).

Trade-offs:
- **Compatibilidade retro** com material antigo, mas **desnecessário** para GitHub e **frágil** (rotação de CA quebra). Fica como fallback documentado caso a AWS passe a exigir para este IdP (improvável).

## 4. Decisão

Criar a nova stack **`03-cicd-oidc-stack`** (Terraform) contendo:

1. **IAM OIDC identity provider do GitHub** (`aws_iam_openid_connect_provider`):
   - `url = "https://token.actions.githubusercontent.com"`;
   - `client_id_list = ["sts.amazonaws.com"]`;
   - **sem `thumbprint_list`** (B1 — a AWS valida via CA para o GitHub);
   - `tags` herdando `adr = "ADR-0004"` via `default_tags`.

2. **IAM Role assumível por Web Identity** (`aws_iam_role` com `assume_role_policy`):
   - `Action = sts:AssumeRoleWithWebIdentity`;
   - `Principal.Federated =` ARN do provider do passo 1;
   - `Condition`:
     - `StringEquals`: `token.actions.githubusercontent.com:aud = "sts.amazonaws.com"`;
     - `StringLike`: `token.actions.githubusercontent.com:sub = "repo:kenerry-serain/dvn-workshop-julho:*"` (parametrizável para restringir por branch/environment — ex.: `repo:kenerry-serain/dvn-workshop-julho:ref:refs/heads/main` — se o time quiser limitar o CD à branch `main`);
   - nome com prefixo `dvn-bigode-` (ex.: `dvn-bigode-github-actions-ecr`), parametrizado.

3. **IAM policy de permissões mínimas de ECR** (`aws_iam_policy` + attachment na role), com **exatamente** as ações do requisito 3:
   - `ecr:GetAuthorizationToken` — **statement à parte com `Resource = "*"`** (esta ação **não** suporta escopo por ARN de repositório; é uma exigência do IAM/ECR);
   - `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage` — **statement escopado aos ARNs dos dois repositórios** (`dvn-workshop/production/backend` e `dvn-workshop/production/frontend`), obtidos do output `ecr_repository_arns` da `02` via `terraform_remote_state` (sem ARN hard-coded).

4. **Consumo da `02` via `data "terraform_remote_state"`** (backend S3, `key = "02-eks-cluster-stack/terraform.tfstate"`) para ler `ecr_repository_arns` e escopar a policy.

5. **Outputs** da stack: o **ARN da role** (`github_actions_role_arn`) — consumido pelos workflows do ADR-0006 como `role-to-assume` — e o **ARN do OIDC provider**.

Justificativa frente aos drivers:
- **Driver 1**: federação OIDC → zero access keys de longa duração; os workflows recebem credenciais efêmeras.
- **Driver 2**: `:sub` restrito ao repositório; policy com só as 6 ações do requisito, escopada por ARN de repo (exceto `GetAuthorizationToken`, que o IAM exige em `*`).
- **Driver 3**: stack e state próprios (`03-...`) — isolada do EKS/rede.
- **Driver 4/5**: mesmo backend/pins/naming/tag; ARNs vêm do remote state da `02`, sem hard-coding.

## 5. Consequências

Positivas:
- CI autentica na AWS **sem** secrets de credencial estática; rotação automática pelo STS.
- Superfície de permissão mínima e escopada; role assumível apenas por este repositório.
- Federação OIDC isolada em stack própria — sobrevive a `destroy` do cluster.
- Base pronta para o ADR-0006 (workflows) referenciarem o `role-to-assume` via output.

Negativas / dívida técnica aceita:
- **Mais uma stack** para operar (`init`/`plan`/`apply`) — custo operacional pequeno.
- **`:sub` com wildcard de repo (`:*`)** permite **qualquer** branch/PR/tag/environment do repositório assumir a role. Aceito para workshop (simplicidade); se o CD precisar ser restrito à `main`, endurecer o `:sub` (parametrizado). PRs de forks **não** recebem o token OIDC por padrão do GitHub, o que reduz o risco.
- **`ecr:GetAuthorizationToken` em `Resource = "*"`**: inevitável (ação não suporta ARN de recurso). Aceito; é o padrão AWS.
- **Acoplamento ao output `ecr_repository_arns` da `02`**: se a `02` renomear/remover esse output, a `03` quebra. Mitigado tratando o output como contrato.
- **Divergência do `ecr-apps.json`** (nomes `devops-na-nuvem/prod/*`) permanece até ser corrigida fora deste ADR.

## 6. Plano de implementação

Passos atômicos, ordenados por dependência. Cada passo tem critério de conclusão verificável. O Engineer decide o "como escrever" (locals, nomes internos, `for_each`). A **organização física dos `.tf` deve seguir a Seção 7** e a **modelagem de variáveis a Seção 6 da rule** `.claude/rules/terraform-naming.md` (sem hard-coding; variável de contexto agrupada em objeto; valores em `*.tfvars`).

0. **Criar `dvn-workshop-terraform/03-cicd-oidc-stack/`** com esqueleto (`versions.tf`, `providers.tf`, `variables.tf`, `outputs.tf`), espelhando a `02`: provider `hashicorp/aws ~> 6.0`, Terraform `~> 1.10`, `region = var.region`, `default_tags = var.default_tags` (incluindo `adr = "ADR-0004"`), backend `s3` no bucket `dvn-bigode-tfstate-654654554686-us-east-1`, `key = "03-cicd-oidc-stack/terraform.tfstate"`, `encrypt = true`, `use_lockfile = true`.
   *Conclusão:* `terraform init` + `validate` limpos na nova stack.

1. **Consumir a `02` via `data "terraform_remote_state"`** (`key = "02-eks-cluster-stack/terraform.tfstate"`); derivar em `locals` a lista de ARNs de repositório ECR a partir do output `ecr_repository_arns` (map → `values(...)`). (arquivo: `cicd.remote-state.tf`)
   *Conclusão:* `plan` resolve os ARNs dos dois repos a partir do remote state, sem ARN hard-coded.

2. **Modelar a variável de contexto** (Seção 6 da rule): um objeto (ex.: `github_oidc`) com `provider_url`, `audience` (lista), `subject_claim` (string do `:sub`, ex.: `repo:kenerry-serain/dvn-workshop-julho:*`), `role_name`, e a lista de ações ECR com escopo por repo. Valores em `terraform.tfvars`. Nenhum literal nos resources. (arquivos: `variables.tf` + `terraform.tfvars`)
   *Conclusão:* `variables.tf` declara a variável com `description`/`type`; `terraform.tfvars` traz os valores; `validate` limpo.

3. **Declarar o OIDC provider do GitHub** (`aws_iam_openid_connect_provider`, `url`, `client_id_list`, **sem** `thumbprint_list`). (arquivo: `cicd.oidc.tf`)
   *Conclusão:* `plan` mostra a criação do provider apontando para `token.actions.githubusercontent.com`.

4. **Declarar o trust document e a role** (`data "aws_iam_policy_document"` para o assume-role com `sts:AssumeRoleWithWebIdentity`, principal Federated = ARN do provider, condition `aud` + `sub`; `aws_iam_role` com esse `assume_role_policy`). (arquivo: `cicd.role.tf`)
   *Conclusão:* `plan` mostra a role com trust restrito ao repositório e à audience.

5. **Declarar a policy de ECR** (`data "aws_iam_policy_document"` com 2 statements — `GetAuthorizationToken` em `*` e as 5 ações de push escopadas aos ARNs dos repos + `:*`/layers conforme necessário; `aws_iam_policy`; `aws_iam_role_policy_attachment`). (arquivo: `cicd.ecr-policy.tf`)
   *Conclusão:* `plan` mostra a policy com exatamente as 6 ações do requisito e o attachment na role.

6. **Expor outputs** (`github_actions_role_arn`, `github_oidc_provider_arn`), padrão `{name}_{type}_{attribute}`. (arquivo: `outputs.tf`)
   *Conclusão:* `terraform output` retorna os ARNs após `apply`.

7. **`plan` + revisão + `apply`** (confirmação humana, guardrails do Engineer).
   *Conclusão:* `apply` conclui; provider e role visíveis em IAM.

8. **Validar** (Seção 11).

## 7. Layout de diretórios

Segue a rule `.claude/rules/terraform-naming.md`, **Seção 5** (um recurso/grupo coeso por arquivo, `<dominio>.<componente>.tf`, prefixo de domínio consistente — aqui `cicd`). Contrato de organização (obrigatório); nomes internos do Terraform ficam a cargo do Engineer.

```
dvn-workshop-terraform/
├── 00-remote-backend-stack/          # existente (ADR-0002)
├── 01-networking-stack/              # existente (ADR-0001)
├── 02-eks-cluster-stack/             # existente (ADR-0003) — cluster EKS + ECR (fonte do remote state)
└── 03-cicd-oidc-stack/               # NOVA stack — federação OIDC GitHub->AWS (este ADR)
    ├── cicd.oidc.tf                  # aws_iam_openid_connect_provider (GitHub, sem thumbprint)
    ├── cicd.role.tf                  # data aws_iam_policy_document (assume-role web identity) + aws_iam_role
    ├── cicd.ecr-policy.tf            # data aws_iam_policy_document (ECR) + aws_iam_policy + role_policy_attachment
    ├── cicd.remote-state.tf          # data terraform_remote_state da 02 + locals (ARNs dos repos ECR)
    ├── variables.tf                  # variável de contexto "github_oidc" + region + default_tags
    ├── terraform.tfvars              # valores (url, audience, subject_claim, role_name, ações ECR)
    ├── outputs.tf                    # github_actions_role_arn, github_oidc_provider_arn
    ├── versions.tf                   # Terraform ~> 1.10 + hashicorp/aws ~> 6.0 + backend s3 (key 03-cicd-oidc-stack/...)
    └── providers.tf                  # provider aws (region = var.region, default_tags)
```

Observações:
- **Sem arquivo central "cicd.tf"**: o domínio `cicd` desta stack é um conjunto de recursos IAM coesos; o recurso mais central é o provider OIDC (`cicd.oidc.tf`). O Engineer pode consolidar/renomear desde que mantenha o prefixo `cicd` e um recurso/grupo coeso por arquivo.
- Nomes internos com `_`, singular, sem repetir o tipo (ex.: `aws_iam_role "github_actions"`).

## 8. Boas práticas aplicáveis

- **Tag obrigatória de rastreabilidade**: **todo recurso desta stack deve carregar `adr = "ADR-0004"`**, aplicado centralmente via `default_tags` no provider (o OIDC provider e a role/policy suportam `tags`). Não sobrescrever a chave `adr` onde houver `tags` próprios.
- **Sem credenciais de longa duração**: nenhuma access key criada; a role é o único caminho de acesso do CI.
- **Least privilege**: exatamente as 6 ações do requisito; ações de push escopadas por ARN de repositório (via remote state), `GetAuthorizationToken` em `*` (limitação do IAM). Não anexar policies gerenciadas amplas (ex.: `AmazonEC2ContainerRegistryPowerUser`).
- **Trust restrito**: `:aud = sts.amazonaws.com` **e** `:sub` restrito ao repositório (`StringLike` com `repo:kenerry-serain/dvn-workshop-julho:*`); nunca `:sub` só wildcard. Parametrizar para permitir endurecer por branch/environment.
- **State**: mesmo padrão do projeto — `backend "s3"` no bucket existente, `key = "03-cicd-oidc-stack/terraform.tfstate"`, `use_lockfile = true`, `encrypt = true`. Não recriar bucket.
- **Modelagem de variáveis (Seção 6 da rule)**: sem hard-coding; objeto de contexto `github_oidc` com valores em `terraform.tfvars`; ARNs de ECR vêm do remote state.
- **Naming/layout**: prefixo `dvn-bigode-` no nome da role; layout `<dominio>.<componente>.tf`; outputs `{name}_{type}_{attribute}` com `description`.
- **Versionamento**: manter `hashicorp/aws ~> 6.0` e Terraform `~> 1.10`; não fazer upgrade dentro deste ADR.

## 9. Riscos e mitigações

- **[NÃO VERIFICADO] Nomes exatos e argumentos dos recursos IAM da role/policy** (`aws_iam_role.assume_role_policy`, `aws_iam_policy`, `aws_iam_role_policy_attachment`, `data "aws_iam_policy_document"` com bloco `principals`/`condition`) não reconfirmados individualmente via MCP nesta sessão além do padrão já usado na `02`. **Mitigação**: o Engineer deve confirmar via MCP `get_provider_details` (hashicorp/aws 6.x) antes de escrever `cicd.role.tf`/`cicd.ecr-policy.tf`. O padrão de trust JSON, porém, está verificado (AWS docs).
- **`ecr:GetAuthorizationToken` não suporta escopo por ARN** — obriga um statement com `Resource = "*"`. **Mitigação**: isolar essa ação em statement próprio; as demais 5 ações permanecem escopadas por ARN. Comportamento esperado e documentado.
- **`:sub` com `:*` permite qualquer ref do repo** assumir a role. **Mitigação**: parametrizado; endurecer para `ref:refs/heads/main` (ou `environment:production`) se o CD deve rodar só na `main`. PRs de forks não recebem token OIDC por default do GitHub.
- **[A RESOLVER] Divergência `ecr-apps.json` (`devops-na-nuvem/prod/*`) vs. repos reais (`dvn-workshop/production/*`)** — se o Engineer escopar a policy pelos nomes do `ecr-apps.json`, o push falhará por ARN inexistente. **Mitigação**: usar **os ARNs do output `ecr_repository_arns` da `02`** como fonte da verdade; sinalizar a correção do `ecr-apps.json` fora deste ADR.
- **Dois OIDC providers na conta (EKS/IRSA da `02` + GitHub desta stack)** — risco de confundir/duplicar. **Mitigação**: `url` distinto (`token.actions.githubusercontent.com` ≠ issuer do EKS); recursos em stacks diferentes.
- **[NÃO VERIFICADO] Existência prévia de um OIDC provider do GitHub na conta `654654554686`** — credenciais AWS indisponíveis nesta sessão para checar via `aws iam list-open-id-connect-providers`. Se já existir um provider para `token.actions.githubusercontent.com`, o `apply` conflita (recurso duplicado). **Mitigação**: o Engineer verifica antes do apply; se existir, importar (`terraform import`) em vez de criar.
- **Rotação de thumbprint** — não aplicável (B1, sem thumbprint). Registrado por completude.
- **Custo**: OIDC provider + role/policy IAM não têm custo direto. Sem risco de custo recorrente.

## 10. Rollback

- **Passos 0–6 (código, pré-apply)**: remover/editar arquivos; nada provisionado.
- **Passo 7 (apply)**: `terraform destroy` da `03-cicd-oidc-stack` remove OIDC provider do GitHub + role + policy. State com `key` própria → destroy isolado; **não** afeta `00`/`01`/`02`. Após o destroy, os workflows do ADR-0006 deixam de conseguir `AssumeRoleWithWebIdentity` (falham no `configure-aws-credentials`) — reverter o CD implica também pausar os workflows.
- **Reverter só o escopo do `:sub`**: ajustar `subject_claim` no `terraform.tfvars` e reaplicar (update in-place do `assume_role_policy`).
- **Reverter só as permissões**: editar a policy no `terraform.tfvars`/`data` e reaplicar (update in-place).
- **OIDC provider importado** (se já existia): `terraform state rm` antes do destroy para não remover um provider compartilhado por outros usos.

## 11. Validação

O Engineer deve comprovar ao final:
1. `terraform validate` e `terraform fmt -check` limpos na `03-cicd-oidc-stack`.
2. State da `03` no S3 (`key = "03-cicd-oidc-stack/terraform.tfstate"`); `plan` **sem mudanças** após o apply (idempotência).
3. OIDC provider `token.actions.githubusercontent.com` presente (IAM → Identity providers), `client_id_list = ["sts.amazonaws.com"]`, criado **sem** thumbprint.
4. IAM Role criada com `assume_role_policy` contendo `sts:AssumeRoleWithWebIdentity`, condition `:aud = sts.amazonaws.com` e `:sub` restrito a `repo:kenerry-serain/dvn-workshop-julho:*` (ou o valor parametrizado).
5. Policy anexada com **exatamente** as 6 ações do requisito; ações de push escopadas aos ARNs dos repos `dvn-workshop/production/backend` e `.../frontend` (vindos do remote state da `02`); `GetAuthorizationToken` em `*`.
6. **Teste ponta-a-ponta (com o ADR-0006 aplicado)**: um workflow rodando no repositório assume a role via `aws-actions/configure-aws-credentials` (sem secrets de chave), faz `aws ecr get-login-password`/login e um `docker push` para um dos repos **com sucesso**; uma tentativa de push para um repo **fora** do escopo é **negada** (comprova least privilege).
7. `terraform output` retorna `github_actions_role_arn` e `github_oidc_provider_arn`.
8. Todos os recursos com a tag `adr=ADR-0004`.

## 12. Premissas

Como o pedido foi para planejar diretamente e alguns dados não puderam ser verificados (credenciais AWS indisponíveis nesta sessão), registro as premissas — cada uma é ponto de validação humana antes/na aprovação:

1. **Repositório GitHub alvo** = `kenerry-serain/dvn-workshop-julho` (verificado em `git remote`). Confirmar se o CD roda a partir deste repo (e não de um fork/monorepo diferente).
2. **[Ponto de validação] Escopo do `:sub`**: assume-se `repo:kenerry-serain/dvn-workshop-julho:*` (qualquer ref). Confirmar se deve ser restrito à branch `main` (`ref:refs/heads/main`) ou a um GitHub environment.
3. **Fonte da verdade dos repos ECR** = `dvn-workshop/production/{backend,frontend}` (da `02`), **não** o `ecr-apps.json` (`devops-na-nuvem/prod/*`, desatualizado). Confirmar e corrigir o `ecr-apps.json` fora deste ADR.
4. **[Ponto de validação — NÃO VERIFICADO] Não existe** ainda um OIDC provider do GitHub na conta `654654554686`. Confirmar via `aws iam list-open-id-connect-providers`; se existir, importar em vez de criar.
5. **Conta única `654654554686`, região `us-east-1`** (herdadas de 00/01/02). Confirmar.
6. **Sem requisito de compliance específico** que exija endurecer além do least privilege já proposto (ex.: permission boundary na role). Confirmar se existir.

---

> **Bloqueado para implementação.** Este ADR aguarda revisão e aprovação humana.
> Para liberar a execução, edite o cabeçalho: `status: Aprovado`, preencha `aprovado_por` e `aprovado_em`, e faça commit em `docs/`.
