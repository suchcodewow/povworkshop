# Standalone shared-services project that hosts the Trivy server. Separate from
# the attendee projects, with its own state, so it can be applied/destroyed on
# its own. deletion_policy = "DELETE" so `terraform destroy` actually removes it.

resource "random_id" "suffix" {
  byte_length = 3 # 6 hex chars
}

resource "google_project" "trivy" {
  name       = var.prefix
  project_id = "${var.prefix}-${random_id.suffix.hex}"

  org_id    = startswith(var.parent, "organizations/") ? split("/", var.parent)[1] : null
  folder_id = startswith(var.parent, "folders/") ? split("/", var.parent)[1] : null

  billing_account = var.billing_account

  # We create our own VPC below.
  auto_create_network = false

  deletion_policy = "DELETE"
}

resource "google_project_service" "compute" {
  project = google_project.trivy.project_id
  service = "compute.googleapis.com"

  disable_on_destroy = false
}
