# Project factory — creates one GCP project per attendee, links billing, and
# enables the APIs the clusters layer needs. Run this FIRST (by someone with
# project-create + billing permissions on the folder/billing account); feed its
# `attendee_projects` output into the clusters layer's terraform.tfvars.

locals {
  # Derive a project-name fragment from each email: take the local part (before
  # @), drop the period between first and last name, and lowercase.
  # e.g. "Shawn.Pearson@harness.io" -> "shawnpearson". The resulting map keys
  # the resources and outputs; duplicate derived names error at plan time.
  attendees = {
    for email in var.attendee_emails :
    replace(lower(split("@", email)[0]), ".", "") => email
  }

  # project_id must be <= 30 chars and is built as "<prefix>-<fragment>-<6 hex>",
  # i.e. len(prefix) + len(fragment) + 8 (two hyphens + 6 hex). Cap the fragment
  # so even a long firstlast fits; the random suffix still keeps IDs unique, and
  # the full firstlast is preserved as the map key / in the attendee_emails output.
  id_fragment_max = 30 - length(var.prefix) - 8

  project_fragment = {
    for name in keys(local.attendees) :
    name => substr(name, 0, min(length(name), local.id_fragment_max))
  }
}

# Short random suffix to keep the globally-unique project_id from colliding.
resource "random_id" "suffix" {
  for_each = local.attendees

  byte_length = 3 # 6 hex chars
}

resource "google_project" "attendee" {
  for_each = local.attendees

  name       = "${var.prefix}-${local.project_fragment[each.key]}"
  project_id = "${var.prefix}-${local.project_fragment[each.key]}-${random_id.suffix[each.key].hex}"

  # Parent under either an org or a folder (google_project takes exactly one).
  org_id    = startswith(var.parent, "organizations/") ? split("/", var.parent)[1] : null
  folder_id = startswith(var.parent, "folders/") ? split("/", var.parent)[1] : null

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
    for pair in setproduct(keys(local.attendees), var.apis) :
    "${pair[0]}::${pair[1]}" => {
      attendee = pair[0]
      api      = pair[1]
    }
  }
}

# Give each attendee admin-level access to their own project. Uses the additive
# *_member (not *_binding) so it won't clobber other IAM on the project. Default
# role is editor; owner can't be granted to external users via the API
# (ORG_MUST_INVITE_EXTERNAL_OWNERS) — see var.attendee_role.
resource "google_project_iam_member" "attendee_admin" {
  for_each = local.attendees

  project = google_project.attendee[each.key].project_id
  role    = var.attendee_role
  member  = "user:${each.value}"
}

# Operator SA: owner on every attendee project, so the impersonated workshop
# runs can fully manage resources in them (registries + their IAM, networks,
# GKE, node SAs + bindings). Scoped to attendee projects, not the org. Skipped
# when var.operator_service_account is null (i.e. not using impersonation).
resource "google_project_iam_member" "operator_owner" {
  for_each = var.operator_service_account == null ? {} : local.attendees

  project = google_project.attendee[each.key].project_id
  role    = "roles/owner"
  member  = "serviceAccount:${var.operator_service_account}"
}

# Shared editors: editor on every attendee project, no project of their own.
# Uses setproduct(attendees × emails) so each shared editor is bound in each
# attendee project via the additive *_member (won't clobber other IAM).
resource "google_project_iam_member" "shared_editors" {
  for_each = {
    for pair in setproduct(keys(local.attendees), var.shared_editor_emails) :
    "${pair[0]}::${pair[1]}" => {
      attendee = pair[0]
      email    = pair[1]
    }
  }

  project = google_project.attendee[each.value.attendee].project_id
  role    = "roles/editor"
  member  = "user:${each.value.email}"
}

resource "google_project_service" "enabled" {
  for_each = local.project_apis

  project = google_project.attendee[each.value.attendee].project_id
  service = each.value.api

  # Don't disable APIs on destroy — avoids ordering/timeout issues while other
  # resources are still tearing down.
  disable_on_destroy = false
}
