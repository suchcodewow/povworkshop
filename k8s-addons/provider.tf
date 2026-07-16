provider "google" {
  # Project of the attendee selected by the current workspace.
  project = local.valid ? local.clusters.attendee_projects[local.attendee] : null
  region  = local.clusters.region
}

# Short-lived OAuth token for the current gcloud/ADC identity.
data "google_client_config" "default" {}

# Configured for the single cluster selected by the current workspace.
provider "kubernetes" {
  host                   = "https://${local.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(local.ca_cert)
}
