---
name: fatos-cicd-gitops-verificados
description: Fatos verificados via MCP/web para CD GitOps (OIDC GitHub->AWS, ArgoCD, helm/kubernetes providers) — base dos ADRs 0004-0006
metadata:
  type: reference
---

Verificados 2026-07-26 (MCP AWS docs, Terraform registry, WebSearch). Não escrever de memória sem reconferir.

**OIDC GitHub Actions -> AWS**
- OIDC provider url = `https://token.actions.githubusercontent.com`, audience (`client_id_list`) = `["sts.amazonaws.com"]`.
- Trust policy: `Action=sts:AssumeRoleWithWebIdentity`, Principal.Federated = ARN do oidc-provider; Condition `StringEquals` sobre `token.actions.githubusercontent.com:aud = sts.amazonaws.com` + `StringLike` sobre `...:sub = repo:OWNER/REPO:*` (ou ref específico). AWS EXIGE que `:sub` não seja só wildcard.
- **Thumbprint hoje é opcional/não-usado para GitHub**: AWS valida o TLS do JWKS contra sua própria library de CAs confiáveis (GitHub/GitLab/Google/Auth0/S3-hosted JWKS). `thumbprint_list` fica retido na config mas NÃO é usado para verificação. Fonte: doc do `aws_iam_openid_connect_provider` (hashicorp/aws 6.56.0, docID 12942122) e AWS CLI update-open-id-connect-provider-thumbprint.
- `aws_iam_openid_connect_provider` (docID 12942122): args `url` (req), `client_id_list` (req), `thumbprint_list` (OPCIONAL agora), `tags`. Exporta `arn`. Pode ser criado SEM thumbprint (exemplo oficial "Without A Thumbprint").
- Condition keys GitHub disponíveis: `sub`, `aud`, `repository`, `ref`, `environment`, `actor`, `job_workflow_ref`, `repository_owner_id`, etc.
- IMPORTANTE: a stack 02 já cria um `aws_iam_openid_connect_provider` para o **EKS/IRSA** (issuer do cluster). O provider do GitHub é OUTRO recurso (url diferente). Não confundir.

**Providers Terraform (últimas versões)**
- `hashicorp/helm` = **3.2.0**. `hashicorp/kubernetes` = **3.2.1**. `hashicorp/aws` = 6.56.0. `hashicorp/tls` = ~>4.0.
- `helm_release` (helm 3.x, docID 12457886): required `name`, `chart`. Optional `repository`, `version`, `namespace`, `create_namespace`, `values` (list of raw yaml strings), `set` (agora BLOCK LIST de objetos {name,value,type}), `wait`, `atomic`, `timeout`. Provider helm 3.x config: bloco `kubernetes = {...}` aninhado (host, cluster_ca_certificate, token/exec).

**ArgoCD**
- Helm chart `argo-cd` do repo `https://argoproj.github.io/argo-helm` (`helm repo add argo https://argoproj.github.io/argo-helm`). Última versão do chart = **10.2.1** (2026-06-09). Chart community-maintained (argoproj). Instala non-HA por default; HA via values. CRDs instaladas por default (crds.install).
- App-of-apps / Application + Kustomize: ArgoCD detecta Kustomize automaticamente se há kustomization.yaml no path. Application CR aponta repoURL + path + targetRevision; syncPolicy.automated {prune, selfHeal}.

**Consolidação de ADRs (2026-07-26)**
- O antigo ADR-0007 (tag por SHA + write-back do kustomize via `kustomize edit set image`) foi **absorvido no ADR-0006** por feedback do usuário: o write-back é apenas o step final do pipeline de CI, não uma decisão arquitetural separada. ADR-0007 foi APAGADO (não havia sido aprovado; não há convenção de marcar removidos no projeto). Numeração deixada como 0004, 0005, 0006 (sem renumerar). ADR-0004 e ADR-0005 tiveram referências a 0007 reapontadas para 0006.
- ADR-0006 agora cobre o pipeline de ponta a ponta: checkout -> OIDC assume-role -> login ECR -> build -> push (tag github.sha) -> kustomize edit set image -> commit&push do manifesto (write-back na main via GITHUB_TOKEN/bot, serializado por concurrency compartilhado + pull --rebase/retry). Permissões: id-token: write + contents: write.

Ver [[infra-estado-atual]] e [[fatos-eks-nativo-verificados]].
