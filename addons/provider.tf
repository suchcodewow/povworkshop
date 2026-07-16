# No default project: each resource sets its own project from the attendee
# project map, so one provider spans all attendee projects.
provider "google" {
  region = local.region
}
