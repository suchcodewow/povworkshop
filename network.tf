# A dedicated VPC + subnet per attendee, each in that attendee's own project.
# Because the networks are isolated in separate projects, every attendee can
# use the same CIDR ranges — no cross-attendee coordination needed.

resource "google_compute_network" "vpc" {
  for_each = toset(local.attendees)

  project                 = var.attendee_projects[each.key]
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  for_each = toset(local.attendees)

  project = var.attendee_projects[each.key]
  name    = "${var.prefix}-subnet"
  region  = var.region
  network = google_compute_network.vpc[each.key].id

  # Let nodes reach Google APIs without a public route — needed once the
  # addon layer restricts general internet egress.
  private_ip_google_access = true

  ip_cidr_range = "10.0.0.0/16"

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.100.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "172.16.0.0/24"
  }
}
