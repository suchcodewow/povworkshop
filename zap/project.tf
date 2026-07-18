# Standalone shared-services project that hosts the OWASP ZAP server. Separate
# from the attendee projects, with its own state, so it can be applied/destroyed
# on its own. deletion_policy = "DELETE" so `terraform destroy` removes it.

resource "random_id" "suffix" {
  byte_length = 3 # 6 hex chars
}

resource "google_project" "zap" {
  name       = "${var.prefix}-scanner" # display name must be >= 4 chars ("zap" is 3)
  project_id = "${var.prefix}-${random_id.suffix.hex}"

  org_id    = startswith(var.parent, "organizations/") ? split("/", var.parent)[1] : null
  folder_id = startswith(var.parent, "folders/") ? split("/", var.parent)[1] : null

  billing_account = var.billing_account

  auto_create_network = false
  deletion_policy     = "DELETE"
}

resource "google_project_service" "compute" {
  project = google_project.zap.project_id
  service = "compute.googleapis.com"

  disable_on_destroy = false
}
