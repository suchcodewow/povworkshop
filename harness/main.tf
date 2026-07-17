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
