locals {
  # Explicit var wins (e.g. pre-existing projects); otherwise auto-populate from
  # the projects/ factory layer's attendee_projects output (see data.tf).
  attendee_projects = length(var.attendee_projects) > 0 ? var.attendee_projects : data.terraform_remote_state.projects[0].outputs.attendee_projects

  # Single source of truth for the attendee list, derived from the project map.
  attendees = sort(keys(local.attendee_projects))
}
