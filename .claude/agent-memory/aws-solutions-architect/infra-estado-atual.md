---
name: infra-estado-atual
description: Estado atual da infraestrutura do projeto dvn-workshop-julho (VPC, região, provider, state backend, EKS, ECR, apps, kubernetes)
metadata:
  type: project
---

Estado da infraestrutura em 2026-07-26 (repo dvn-workshop-julho):

- **Infra organizada em STACKS numeradas** em `dvn-workshop-terraform/`: `00-remote-backend-stack`, `01-networking-stack`, `02-eks-cluster-stack`. Convenção `NN-<nome>-stack`.
- **Conta AWS = `654654554686`**, região `us-east-1`.
- Provider `hashicorp/aws ~> 6.0`, lock `6.56.0`. Terraform `~> 1.10`. Provider usa `region = var.region` e `default_tags = var.default_tags` ({Environment=production, Project=dvn-workshop-julho, adr=ADR-NNNN}).
- **Backend remoto S3 ATIVO**: bucket `dvn-bigode-tfstate-654654554686-us-east-1` (ADR-0002, Aprovado). Key por stack, `use_lockfile = true`, `encrypt = true`.
- **`01-networking-stack`**: VPC `10.0.0.0/24`, 2 subnets públicas + 2 privadas em us-east-1a/1b. Outputs: `vpc_id`, `vpc_cidr_block`, `public_subnet_ids` (map), `private_subnet_ids` (map), etc.
- **`02-eks-cluster-stack` (ADR-0003, agora Aprovado, Kenerry Serain, 2026-07-26)**: cluster EKS `dvn-bigode-eks`, K8s **1.36**, recursos NATIVOS (sem módulo), node group ON_DEMAND t3.medium desired2/min2/max4, `authentication_mode=API_AND_CONFIG_MAP`, OIDC/IRSA provider criado, `bootstrap_cluster_creator_admin_permissions=true`. Outputs relevantes p/ CD: `eks_cluster_name`, `eks_cluster_endpoint`, `eks_cluster_certificate_authority_data`, `eks_cluster_oidc_issuer_url`, `eks_openid_connect_provider_arn/url`, `ecr_repository_urls` (map name=>url), `ecr_repository_arns`.
- **ECR criado DENTRO da 02** (`ecr.tf`, `var.ecr_repositories`): repos `dvn-workshop/production/backend` e `dvn-workshop/production/frontend` (MUTABLE, scan_on_push). URLs `654654554686.dkr.ecr.us-east-1.amazonaws.com/dvn-workshop/production/{backend,frontend}`.
- **Apps** em `dvn-workshop-apps/`: backend `backend/YoutubeLiveApp` (ASP.NET net8.0, porta 8080, health `/backend/health`, Dockerfile multi-stage user app UID 1654) e frontend `frontend/youtube-live-app` (Next.js 14 standalone, porta 3000, health `/api/health`, user node). `ecr-apps.json` cita repos `devops-na-nuvem/prod/*` (DIVERGE dos repos reais `dvn-workshop/production/*` da 02 — inconsistência a resolver).
- **Kubernetes** em `dvn-workshop-kubernetes/` (Kustomize): `kustomization.yaml` raiz (namespace `dvn-workshop`, resources namespace.yaml/backend/frontend, bloco `images:` mapeando `dvn-workshop/production/{backend,frontend}` -> newName ECR + newTag). Componentes backend/ e frontend/ com deployment.yaml+service.yaml(NodePort)+pdb.yaml+kustomization.yaml. Seguem rule kubernetes-manifests.md (replicas>=2, probes, PDB, labels app.kubernetes.io/*). Imagem no deployment usa nome lógico `dvn-workshop/production/backend|frontend` (tag resolvida pelo bloco images:).
- **Repo GitHub**: `kenerry-serain/dvn-workshop-julho` (origin https). SEM diretório `.github/` ainda.

**Why:** Base para qualquer ADR de infra/CD deste projeto.
**How to apply:** Nova infra vai em stack numerada própria. CD (OIDC/ArgoCD) consome outputs da 02 via remote state. Ver [[convencoes-projeto]], [[fatos-aws-verificados]], [[fatos-terraform-backend-s3]], [[fatos-eks-nativo-verificados]], [[fatos-cicd-gitops-verificados]].
