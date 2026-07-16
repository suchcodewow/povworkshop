locals {
  # Single source of truth for the attendee list, derived from the project map.
  attendees = sort(keys(var.attendee_projects))
}
