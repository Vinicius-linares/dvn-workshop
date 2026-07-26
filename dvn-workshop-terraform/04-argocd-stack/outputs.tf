output "argocd_namespace" {
  description = "Kubernetes namespace where Argo CD is installed."
  value       = helm_release.argo_cd.namespace
}

output "argocd_chart_version" {
  description = "Installed version of the argo-cd Helm chart."
  value       = helm_release.argo_cd.version
}

output "argocd_application_name" {
  description = "Name of the Argo CD Application managing dvn-workshop-kubernetes."
  value       = kubernetes_manifest.application.manifest.metadata.name
}
