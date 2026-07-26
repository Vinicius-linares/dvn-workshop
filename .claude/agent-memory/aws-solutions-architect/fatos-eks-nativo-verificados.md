---
name: fatos-eks-nativo-verificados
description: Argumentos exatos dos recursos EKS nativos do provider hashicorp/aws 6.x, verificados via MCP (para ADRs de EKS sem módulo comunitário)
metadata:
  type: reference
---

Recursos nativos EKS confirmados via MCP `get_provider_details` (hashicorp/aws 6.56.0, 2026-07-26). Nomes exatos — não escrever de memória sem reconferir.

- **aws_eks_cluster** (docID 12941989): obrigatórios `name`, `role_arn`, `vpc_config`. `vpc_config { subnet_ids (>=2 AZs), endpoint_private_access (def false), endpoint_public_access (def true), public_access_cidrs, security_group_ids }`. `access_config { authentication_mode (CONFIG_MAP|API|API_AND_CONFIG_MAP), bootstrap_cluster_creator_admin_permissions (def true) }`. Log types: argumento **`enabled_cluster_log_types`** (NÃO `enabled_log_types`). Versão K8s: argumento **`version`** (NÃO `kubernetes_version`). Exporta `identity[0].oidc[0].issuer`, `certificate_authority[0].data`, `endpoint`, `arn`.
- **aws_eks_node_group** (docID 12941992): obrigatórios `cluster_name`, `node_role_arn`, `subnet_ids`, `scaling_config { desired_size, max_size, min_size }`. `capacity_type` (ON_DEMAND|SPOT), `instance_types` (def ["t3.medium"]), `update_config { max_unavailable | max_unavailable_percentage | update_strategy }`.
- **aws_eks_access_entry** (docID 12941985): `cluster_name`, `principal_arn`, `type` (def STANDARD), `kubernetes_groups`, `user_name`.
- **aws_eks_access_policy_association** (docID 12941986): `cluster_name`, `policy_arn`, `principal_arn`, `access_scope { type (namespace|cluster), namespaces }`. Admin: `arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy` + type=cluster.
- **aws_iam_openid_connect_provider** (docID 12942122) + `data tls_certificate` (provider hashicorp/tls) = IRSA. url=issuer, client_id_list=["sts.amazonaws.com"], thumbprint_list do fingerprint. Atributos exatos do tls_certificate NÃO verificados — reconferir provider tls.
- **aws_cloudwatch_log_group** (docID 12941662): log group /aws/eks/<name>/cluster; criar antes do cluster (depends_on) senão conflita com o que o EKS cria sozinho.

Managed policies (exemplos oficiais): cluster role -> AmazonEKSClusterPolicy (+ AmazonEKSVPCResourceController); node role -> AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly. Trust: cluster=eks.amazonaws.com (sts:AssumeRole+sts:TagSession), node=ec2.amazonaws.com. Cluster/node group precisam `depends_on` nos policy attachments (senão destroy falha).

Equivalências módulo->nativo: enable_cluster_creator_admin_permissions -> access_config.bootstrap_cluster_creator_admin_permissions; enable_irsa -> aws_iam_openid_connect_provider+tls_certificate; enabled_log_types -> enabled_cluster_log_types; kubernetes_version -> version.

Usado no ADR-0003 (recursos nativos, sem terraform-aws-modules/eks/aws). Ver [[fatos-aws-verificados]].
