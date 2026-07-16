# Per-attendee node service account, in that attendee's own project. Each
# cluster's nodes run as their own identity so access is least-privilege and
# scoped to that project (e.g. read only their own Artifact Registry repo).

resource "google_service_account" "node" {
  for_each = toset(local.attendees)

  project = var.attendee_projects[each.key]
  # account_id must be 6-30 chars; keep attendee names short.
  account_id   = "${var.prefix}-${each.key}-node"
  display_name = "GKE node SA for ${each.key}"
}

locals {
  # Minimal roles GKE nodes need for logging, monitoring, and metadata.
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ]

  # attendee × role -> one binding each (in the attendee's own project).
  node_role_bindings = {
    for pair in setproduct(local.attendees, local.node_sa_roles) :
    "${pair[0]}::${pair[1]}" => {
      attendee = pair[0]
      role     = pair[1]
    }
  }
}

resource "google_project_iam_member" "node_sa" {
  for_each = local.node_role_bindings

  project = var.attendee_projects[each.value.attendee]
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.node[each.value.attendee].email}"
}
