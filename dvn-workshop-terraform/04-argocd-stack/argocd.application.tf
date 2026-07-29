resource "kubernetes_manifest" "application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = var.argocd.application.name
      namespace = var.argocd.namespace
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/part-of"    = "dvn-workshop-julho"
      }
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.argocd.application.repo_url
        path           = var.argocd.application.path
        targetRevision = var.argocd.application.target_revision
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.argocd.application.dest_namespace
      }
      syncPolicy = {
        automated = {
          prune    = var.argocd.application.automated_prune
          selfHeal = var.argocd.application.automated_self_heal
        }
        syncOptions = [
          "CreateNamespace=false"
        ]
      }
    }
  }
}
