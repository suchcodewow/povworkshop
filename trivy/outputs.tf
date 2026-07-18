output "project_id" {
  description = "ID of the standalone Trivy project."
  value       = google_project.trivy.project_id
}

output "trivy_ip" {
  description = "Public IP of the Trivy server."
  value       = google_compute_address.trivy.address
}

output "trivy_endpoint" {
  description = "Trivy server endpoint attendees point their client at."
  value       = "http://${google_compute_address.trivy.address}:${var.trivy_port}"
}

output "trivy_client_example" {
  description = "Example command for attendees (run from a laptop/Cloud Shell, not inside the restricted clusters)."
  value       = "trivy image --server http://${google_compute_address.trivy.address}:${var.trivy_port} <IMAGE>"
}
