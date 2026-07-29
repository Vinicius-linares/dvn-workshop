# ArgoCD Application CR (argoproj.io/v1alpha1).
# apiVersion confirmed via list_api_versions after chart install — the CRD
# is registered by the argo-cd Helm chart (argoproj.github.io/argo-helm 10.2.1).
# depends_on ensures the CRDs exist before the provider validates this manifest.
resource "kubernetes_manifest" "application" {
  depends_on = [helm_release.argo_cd]

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
        syncOptions = ["CreateNamespace=false"]
      }
    }
  }

  computed_fields = ["metadata.annotations", "metadata.labels", "metadata.finalizers"]
}
