# ---------------------------------------------------------------------------
# Binary Authorization — allowlist image registries, one policy per attendee
# project.
#
# At pod-admission time, images matching an allowlist pattern are admitted;
# everything else is DENIED, so a blocked image is never pulled. The policy is
# a per-project singleton, so with a project per attendee each attendee gets
# their own independent policy (each cluster opts in via its
# binary_authorization block in ../gke.tf).
#
# Requires the Binary Authorization API enabled in EACH attendee project:
#   gcloud services enable binaryauthorization.googleapis.com --project <id>
# ---------------------------------------------------------------------------

resource "google_binary_authorization_policy" "policy" {
  for_each = toset(local.attendees)

  project = local.attendee_projects[each.key]

  # Exempt Google-managed GKE system images (kube-system, etc.) so the clusters
  # keep running — without this, system pods would be blocked too.
  global_policy_evaluation_mode = "ENABLE"

  # Allow images from this attendee's own registries; edit to add more.
  dynamic "admission_whitelist_patterns" {
    for_each = [
      "${local.region}-docker.pkg.dev/${local.attendee_projects[each.key]}/*", # Artifact Registry (regional)
      "gcr.io/${local.attendee_projects[each.key]}/*",                         # legacy Container Registry
    ]
    content {
      name_pattern = admission_whitelist_patterns.value
    }
  }

  # Anything not matching the allowlist is denied (and audit-logged).
  default_admission_rule {
    evaluation_mode  = "ALWAYS_DENY"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  }
}
