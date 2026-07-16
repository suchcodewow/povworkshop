# ---------------------------------------------------------------------------
# Limit internet access, per attendee.
#
# Egress firewall rules scoped to each attendee's node tag. Lower `priority`
# numbers win, so the specific "allow" rules override the broad "deny".
#
# Net effect for each attendee's nodes:
#   - allowed : traffic to internal/private ranges + Google APIs
#   - denied  : everything else (general internet)
#
# NOTE: With Private Google Access enabled on the subnets, in-cluster access to
# Google APIs keeps working. Pulling images from public registries (Docker Hub,
# quay.io, etc.) WILL be blocked once these rules apply — which is usually the
# point of the exercise. To also route *.googleapis.com to the restricted VIP
# by DNS, add a private DNS zone; for a workshop demo the rules below are enough
# to show internet egress being cut off.
# ---------------------------------------------------------------------------

# Deny all egress to the internet (broad, low priority).
resource "google_compute_firewall" "deny_internet_egress" {
  for_each = toset(local.attendees)

  project   = local.attendee_projects[each.key]
  name      = "${local.prefix}-${each.key}-deny-egress"
  network   = local.network_names[each.key]
  direction = "EGRESS"
  priority  = 1000

  deny {
    protocol = "all"
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = [local.node_tags[each.key]]
}

# Allow egress to internal/private ranges (nodes <-> pods <-> services, metadata).
resource "google_compute_firewall" "allow_internal_egress" {
  for_each = toset(local.attendees)

  project   = local.attendee_projects[each.key]
  name      = "${local.prefix}-${each.key}-allow-internal-egress"
  network   = local.network_names[each.key]
  direction = "EGRESS"
  priority  = 900

  allow {
    protocol = "all"
  }

  destination_ranges = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
  ]
  target_tags = [local.node_tags[each.key]]
}

# Allow egress to Google APIs via the restricted VIP (Private Google Access).
resource "google_compute_firewall" "allow_google_apis_egress" {
  for_each = toset(local.attendees)

  project   = local.attendee_projects[each.key]
  name      = "${local.prefix}-${each.key}-allow-google-apis-egress"
  network   = local.network_names[each.key]
  direction = "EGRESS"
  priority  = 900

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  destination_ranges = [
    "199.36.153.4/30", # restricted.googleapis.com
    "199.36.153.8/30", # private.googleapis.com
  ]
  target_tags = [local.node_tags[each.key]]
}
