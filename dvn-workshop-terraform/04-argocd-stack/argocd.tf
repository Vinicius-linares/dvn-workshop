resource "helm_release" "argo_cd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd.chart_version
  namespace        = var.argocd.namespace
  create_namespace = true
  wait             = false
  cleanup_on_fail  = true

  values = [
    <<-EOT
    server:
      replicas: 1
      service:
        type: ClusterIP
    controller:
      replicas: 1
    repoServer:
      replicas: 1
    applicationSet:
      enabled: false
    notifications:
      enabled: false
    dex:
      enabled: false
    redis:
      enabled: true
    EOT
  ]
}
