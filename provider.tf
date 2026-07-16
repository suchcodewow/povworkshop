# No default project: each resource sets its own project from
# var.attendee_projects, so one provider spans all attendee projects.
provider "google" {
  region = var.region
}
