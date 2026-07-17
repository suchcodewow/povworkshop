# The workshop organization. Its identifier ("<month>_int", e.g. july_int) and
# name ("<Month>_INT", e.g. July_INT) are derived from the current month by
# workshop.py and passed in as TF_VAR_org_identifier / TF_VAR_org_name. The
# identifier changes month to month, so re-applying in a new month creates a new
# org (identifier is immutable — Harness replaces the resource).
#
# Downstream Harness resources (projects, pipelines, connectors) would set
# org_id = harness_platform_organization.workshop.id.
resource "harness_platform_organization" "workshop" {
  identifier  = var.org_identifier
  name        = var.org_name
  description = var.org_description
  tags        = var.org_tags

  # The values are computed by workshop.py (stable within a month, so no churn).
  # A bare `tofu` run has them unset — fail clearly rather than send nulls.
  lifecycle {
    precondition {
      condition     = var.org_identifier != null && var.org_name != null
      error_message = "org_identifier/org_name are unset. Run via `python3 workshop.py` (it derives them from the current month), or export TF_VAR_org_identifier and TF_VAR_org_name (or pass -var)."
    }
  }
}

locals {
  # firstlast identifier -> email. Mirrors the projects/ layer's derivation
  # (replace(lower(local-part), ".", "")) so each Harness project's identifier
  # lines up with that attendee's GCP project (e.g. "shawnpearson").
  attendees = {
    for email in var.attendee_emails :
    replace(lower(split("@", email)[0]), ".", "") => email
  }

  # First + last name from the email local part:
  # "shawn.pearson@harness.io" -> "Shawn Pearson".
  attendee_names = {
    for key, email in local.attendees :
    key => join(" ", [for part in split(".", split("@", email)[0]) : title(part)])
  }
}

# One Harness project per attendee, inside the workshop org. Depends on the org
# implicitly via org_id, so Terraform creates the org first.
resource "harness_platform_project" "attendee" {
  for_each = local.attendees

  identifier = each.key
  name       = local.attendee_names[each.key]
  org_id     = harness_platform_organization.workshop.id
}
