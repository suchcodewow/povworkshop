# Project factory — creates one GCP project per attendee, links billing, and
# enables the APIs the clusters layer needs. Run this FIRST (by someone with
# project-create + billing permissions on the folder/billing account); feed its
# `attendee_projects` output into the clusters layer's terraform.tfvars.

# Short random suffix to keep the globally-unique project_id from colliding.
resource "random_id" "suffix" {
  for_each = toset(var.attendees)

  byte_length = 3 # 6 hex chars
}

resource "google_project" "attendee" {
  for_each = toset(var.attendees)

  name       = "${var.prefix}-${each.key}"
  project_id = "${var.prefix}-${each.key}-${random_id.suffix[each.key].hex}"

  folder_id       = var.folder_id
  billing_account = var.billing_account

  # We create our own VPC in the clusters layer — skip the default network.
  auto_create_network = false

  # Protect the projects — `terraform destroy` will error rather than delete
  # them. Change to "DELETE" if you want teardown to remove the projects.
  deletion_policy = "PREVENT"
}

locals {
  # attendee × api -> one enablement each.
  project_apis = {
    for pair in setproduct(var.attendees, var.apis) :
    "${pair[0]}::${pair[1]}" => {
      attendee = pair[0]
      api      = pair[1]
    }
  }
}

resource "google_project_service" "enabled" {
  for_each = local.project_apis

  project = google_project.attendee[each.value.attendee].project_id
  service = each.value.api

  # Don't disable APIs on destroy — avoids ordering/timeout issues while other
  # resources are still tearing down.
  disable_on_destroy = false
}
