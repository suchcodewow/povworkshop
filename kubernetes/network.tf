# A dedicated VPC + subnet per attendee, each in that attendee's own project.
# Because the networks are isolated in separate projects, every attendee can
# use the same CIDR ranges — no cross-attendee coordination needed.

resource "google_compute_network" "vpc" {
  for_each = toset(local.attendees)

  project                 = local.attendee_projects[each.key]
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  for_each = toset(local.attendees)

  project = local.attendee_projects[each.key]
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

# ---------------------------------------------------------------------------
# Restricted Google API access for private nodes.
#
# With private nodes (no external IPs) and the addon egress firewall denying
# general internet, nodes reach Google APIs / gcr.io / Artifact Registry only
# via the restricted VIP (199.36.153.4/30 — the range the firewall allows). That
# requires (a) a route to the VIP and (b) private DNS routing those domains to
# it. Without this, image pulls resolve to normal public IPs and get blocked,
# leaving nodes NotReady.
# ---------------------------------------------------------------------------

# Ensure the restricted VIP is routed via the internet gateway (Private Google
# Access carries it without an external IP).
resource "google_compute_route" "restricted_vip" {
  for_each = toset(local.attendees)

  project          = local.attendee_projects[each.key]
  name             = "${var.prefix}-restricted-googleapis"
  network          = google_compute_network.vpc[each.key].name
  dest_range       = "199.36.153.4/30"
  next_hop_gateway = "default-internet-gateway"
}

locals {
  restricted_vip = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]

  # Domains to redirect to the restricted VIP. `apex` gets the A record; the
  # wildcard CNAMEs to it. googleapis.com covers *.googleapis.com; gcr.io and
  # pkg.dev cover Container/Artifact Registry image pulls.
  google_dns_zones = {
    googleapis = { dns_name = "googleapis.com.", apex = "restricted.googleapis.com.", wildcard = "*.googleapis.com." }
    gcr        = { dns_name = "gcr.io.", apex = "gcr.io.", wildcard = "*.gcr.io." }
    pkgdev     = { dns_name = "pkg.dev.", apex = "pkg.dev.", wildcard = "*.pkg.dev." }
  }

  # attendee × zone -> flattened for for_each.
  attendee_zones = {
    for pair in setproduct(local.attendees, keys(local.google_dns_zones)) :
    "${pair[0]}::${pair[1]}" => {
      attendee = pair[0]
      zone     = pair[1]
    }
  }
}

resource "google_dns_managed_zone" "google_apis" {
  for_each = local.attendee_zones

  project     = local.attendee_projects[each.value.attendee]
  name        = "${var.prefix}-${each.value.attendee}-${each.value.zone}"
  dns_name    = local.google_dns_zones[each.value.zone].dns_name
  description = "Route ${local.google_dns_zones[each.value.zone].dns_name} to the restricted Google VIP"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc[each.value.attendee].id
    }
  }
}

resource "google_dns_record_set" "apex_a" {
  for_each = local.attendee_zones

  project      = local.attendee_projects[each.value.attendee]
  managed_zone = google_dns_managed_zone.google_apis[each.key].name
  name         = local.google_dns_zones[each.value.zone].apex
  type         = "A"
  ttl          = 300
  rrdatas      = local.restricted_vip
}

resource "google_dns_record_set" "wildcard_cname" {
  for_each = local.attendee_zones

  project      = local.attendee_projects[each.value.attendee]
  managed_zone = google_dns_managed_zone.google_apis[each.key].name
  name         = local.google_dns_zones[each.value.zone].wildcard
  type         = "CNAME"
  ttl          = 300
  rrdatas      = [local.google_dns_zones[each.value.zone].apex]
}
