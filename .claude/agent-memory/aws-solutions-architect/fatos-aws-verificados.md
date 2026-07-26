---
name: fatos-aws-verificados
description: Fatos AWS/Terraform verificados via MCP que se repetem em ADRs de rede
metadata:
  type: reference
---

Fatos confirmados via MCP AWS/Terraform (2026-07-25), reutilizáveis:

- **Subnet reside inteiramente em UMA AZ** e não pode abranger zonas (VPC User Guide / VPC FAQ). Para HA, distribuir subnets em AZs distintas.
- **NAT Gateway**: HA confinada a uma única AZ. Recomendação AWS: 1 NAT GW por AZ para evitar SPOF e cobrança de tráfego inter-AZ. Single NAT GW = ponto único de falha + custo de dados cross-AZ quando subnets privadas estão em outra AZ.
- **Provider aws 6.56.0** (última). Recurso `aws_nat_gateway` no 6.x suporta `availability_mode` = `zonal` (default) ou `regional` (NAT gateway regional multi-AZ gerenciado, auto ou manual mode). Isso é alternativa de HA relevante a citar.
- `aws_subnet`: args-chave `vpc_id` (req), `cidr_block`, `availability_zone`, `map_public_ip_on_launch` (default false).
- `aws_nat_gateway` zonal público: `allocation_id` (EIP), `subnet_id`, recomenda-se `depends_on` no IGW.
- Route tables: `aws_route_table`, `aws_route_table_association`. IGW: `aws_internet_gateway`. EIP: `aws_eip` (arg `domain = "vpc"`).

**Why:** Evita reconsultar MCP e sustenta o trade-off de custo vs HA do NAT GW único.
**How to apply:** Citar nos ADRs de rede. Ver [[infra-estado-atual]].

## EKS — versões Kubernetes (verificado via AWS docs 2026-07-26)
- Standard support atual: **1.36, 1.35, 1.34, 1.33**. Mais recente = **1.36** (EKS release 2026-06-02, end of standard support 2027-08-02).
- No módulo terraform-aws-modules/eks v21 a variável é `kubernetes_version` (string tipo "1.36"), default null.

## EKS — Access Entries / authentication_mode (verificado)
- authentication_mode válidos: `CONFIG_MAP`, `API`, `API_AND_CONFIG_MAP`. Default do módulo v21 = `API_AND_CONFIG_MAP`.
- Access policy admin de cluster: ARN `arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy`, access-scope `type=cluster` (equivale a system:masters; ok dev/POC, evitar prod — usar AmazonEKSAdminPolicy p/ namespace).
- Módulo v21: `enable_cluster_creator_admin_permissions` (bool, default false) adiciona o principal do Terraform como admin via access entry.

## terraform-aws-modules/eks/aws v21.24.0 (verificado via MCP get_module_details)
- required_version Terraform >= 1.5.7; provider aws >= 6.52 (compatível com pin ~> 6.0 do projeto, lock 6.56.0).
- Vars: `name`, `kubernetes_version`, `vpc_id`, `subnet_ids`, `control_plane_subnet_ids`, `authentication_mode`, `enabled_log_types` (default ["audit","api","authenticator"]; possíveis: api,audit,authenticator,controllerManager,scheduler), `endpoint_public_access` (default false), `endpoint_private_access` (default true), `enable_irsa` (default true, cria OIDC provider), `access_entries` (map(object)), `enable_cluster_creator_admin_permissions` (default false), `create_iam_role` (default true).
- Node groups: `eks_managed_node_groups` = map(object) com `instance_types`, `capacity_type` ("ON_DEMAND"), `min_size`/`max_size`/`desired_size`, `create_iam_role`.
- Outputs: cluster_name, cluster_endpoint, cluster_arn, cluster_certificate_authority_data, cluster_oidc_issuer_url, oidc_provider_arn, cluster_iam_role_arn, access_entries, eks_managed_node_groups, cluster_security_group_id, node_security_group_id.

## Itens NÃO VERIFICÁVEIS nesta sessão
- Caller identity (aws sts get-caller-identity): AWS MCP token expira; CLI local sem credenciais. Account id do backend = 654654554686 (us-east-1). ARN do principal que roda o Terraform precisa de confirmação humana p/ o access entry manual (o toggle enable_cluster_creator_admin_permissions resolve sem precisar do ARN).
