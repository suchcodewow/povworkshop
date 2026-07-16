# One Artifact Registry (Docker) repository per attendee, in that attendee's own
# project. Images pushed here live at:
#   <region>-docker.pkg.dev/<attendee-project>/<prefix>-<attendee>/...
# which matches that project's Binary Authorization allowlist (../addons/binauthz.tf),
# so these images are admitted while others are blocked.

resource "google_artifact_registry_repository" "attendee" {
  for_each = toset(local.attendees)

  project       = var.attendee_projects[each.key]
  location      = var.region
  repository_id = "${var.prefix}-${each.key}"
  description   = "Workshop container images for ${each.key}"
  format        = "DOCKER"
}

# Each attendee's nodes run as their own service account (service_accounts.tf).
# Grant that SA reader access to ONLY that attendee's repo.
resource "google_artifact_registry_repository_iam_member" "node_reader" {
  for_each = google_artifact_registry_repository.attendee

  project    = each.value.project
  location   = each.value.location
  repository = each.value.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.node[each.key].email}"
}
