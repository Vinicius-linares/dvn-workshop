---
name: infra-estado-argocd
description: Stack 04-argocd-stack aplicada — ArgoCD instalado via Helm, Application dvn-workshop sincronizando dvn-workshop-kubernetes/ com prune+selfHeal.
metadata:
  type: project
---

Stack `04-argocd-stack` aplicada em 2026-07-26 (ADR-0005, Kenerry Serain).

**ArgoCD:**
- Chart: `argo-cd 10.2.1` (argoproj.github.io/argo-helm), ArgoCD versão `v3.4.5`
- Namespace: `argocd`, 7 pods Running
- Server: ClusterIP (sem exposição pública); acesso via `kubectl port-forward svc/argocd-server -n argocd 8080:443`
- State S3 key: `04-argocd-stack/terraform.tfstate`

**Application:**
- Nome: `dvn-workshop`, namespace `argocd`
- `source.repoURL = https://github.com/kenerry-serain/dvn-workshop-julho`
- `source.path = dvn-workshop-kubernetes`, `targetRevision = main`
- `syncPolicy.automated { prune = true, selfHeal = true }`
- `apiVersion = argoproj.io/v1alpha1` (confirmado via list_api_versions após install)

**Workloads sincronizados (namespace dvn-workshop):**
- backend: 2 réplicas (tag v2, imagem ECR dvn-workshop/production/backend)
- frontend: 2 réplicas (tag v1, imagem ECR dvn-workshop/production/frontend)

**Providers Terraform:**
- `helm 3.2.0`, `kubernetes 3.2.1`, `aws 6.56.0`
- Auth: `exec` com `aws eks get-token` (token não persiste no state)
- helm provider exec: `api_version = client.authentication.k8s.io/v1beta1`
- kubernetes provider exec: `api_version = client.authentication.k8s.io/v1`

**Operação em 2 fases:** CRDs do ArgoCD não existem no plan inicial; aplicar helm_release com `-target` primeiro, depois apply completo para o kubernetes_manifest Application. Esta é a sequência necessária para novos clusters.

**helm repo:** Adicionado `argo https://argoproj.github.io/argo-helm` no `~/.helm/repositories.yaml` e `helm repo update` executado para popular o cache local (necessário para o provider Terraform).

**Why:** GitOps declarativo; Application única para todo o dvn-workshop-kubernetes/.
**How to apply:** Ao recriar o cluster, rodar a stack 04 em 2 fases: `-target=helm_release.argo_cd` primeiro, depois `apply` completo. Ver [[infra-remote-backend]].
