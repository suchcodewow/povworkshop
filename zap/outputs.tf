output "project_id" {
  description = "ID of the standalone ZAP project."
  value       = google_project.zap.project_id
}

output "zap_ip" {
  description = "Public IP of the ZAP server."
  value       = google_compute_address.zap.address
}

output "zap_endpoint" {
  description = "ZAP API base URL attendees point their client at."
  value       = "http://${google_compute_address.zap.address}:${var.zap_port}"
}

output "zap_api_key" {
  description = "API key required on every ZAP API request (see zap_client_example)."
  value       = local.api_key
  sensitive   = true
}

output "zap_client_example" {
  description = "Quick check the daemon is up (run from an allowed source IP). Reveal the key with: tofu output -raw zap_api_key"
  value       = "curl 'http://${google_compute_address.zap.address}:${var.zap_port}/JSON/core/view/version/?apikey=<zap_api_key>'"
}
