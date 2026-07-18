variable "attendee_roles" {
  description = <<-EOT
    IAM roles granted to each attendee on their own project so they can manage
    their GKE cluster. Defaults to Kubernetes Engine Admin, which includes
    container.clusterRoleBindings.create — required to apply manifests with
    cluster-scoped RBAC (e.g. the Harness delegate). Add more roles here if
    attendees need them.
  EOT
  type        = list(string)
  default     = ["roles/container.admin"]
}
