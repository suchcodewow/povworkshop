output "cluster_names" {
  description = "Map of attendee -> cluster name."
  value       = { for name, c in google_container_cluster.primary : name => c.name }
}

output "cluster_endpoints" {
  description = "Map of attendee -> Kubernetes API server endpoint."
  value       = { for name, c in google_container_cluster.primary : name => c.endpoint }
  sensitive   = true
}

output "cluster_ca_certificates" {
  description = "Map of attendee -> base64 cluster CA cert (for the kubernetes provider)."
  value       = { for name, c in google_container_cluster.primary : name => c.master_auth[0].cluster_ca_certificate }
  sensitive   = true
}

output "get_credentials_commands" {
  description = "Per-attendee command to configure kubectl for their cluster."
  value = {
    for name, c in google_container_cluster.primary :
    name => "gcloud container clusters get-credentials ${c.name} --zone ${var.zone} --project ${local.attendee_projects[name]}"
  }
}

output "artifact_registry_repos" {
  description = "Map of attendee -> Docker repo path to tag/push images to."
  value = {
    for name, r in google_artifact_registry_repository.attendee :
    name => "${r.location}-docker.pkg.dev/${r.project}/${r.repository_id}"
  }
}

# --- Consumed by the addons/ and k8s-addons/ layers via terraform_remote_state ---

output "attendee_projects" {
  description = "Map of attendee -> project ID."
  value       = local.attendee_projects
}

output "region" {
  description = "Region of the networks/registries."
  value       = var.region
}

output "prefix" {
  description = "Resource name prefix."
  value       = var.prefix
}

output "attendees" {
  description = "List of attendee identifiers."
  value       = local.attendees
}

output "network_names" {
  description = "Map of attendee -> that attendee's VPC name."
  value       = { for name, n in google_compute_network.vpc : name => n.name }
}

output "node_tags" {
  description = "Map of attendee -> the network tag on that attendee's nodes."
  value       = { for name in local.attendees : name => "${var.prefix}-${name}" }
}
