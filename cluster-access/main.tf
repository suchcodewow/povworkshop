# Grant each attendee the configured role(s) on their own project. Additive
# *_member bindings (not *_binding), so they don't clobber other IAM. Reads the
# attendee list from the projects factory's state — no inputs needed here.

locals {
  # attendee x role -> one binding each.
  bindings = {
    for pair in setproduct(keys(local.attendee_emails), var.attendee_roles) :
    "${pair[0]}::${pair[1]}" => {
      attendee = pair[0]
      role     = pair[1]
    }
  }
}

resource "google_project_iam_member" "attendee" {
  for_each = local.bindings

  project = local.attendee_projects[each.value.attendee]
  role    = each.value.role
  member  = "user:${local.attendee_emails[each.value.attendee]}"
}
