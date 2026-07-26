# Central resource for the argocd domain: the Helm release of Argo CD.
# Installed non-HA (workshop) with server as ClusterIP (no public exposure).
# Access the UI via: kubectl port-forward svc/argocd-server -n argocd 8080:443
resource "helm_release" "argo_cd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd.chart_version
  namespace        = var.argocd.namespace
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }
      }
    })
  ]
}
