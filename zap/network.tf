# Minimal VPC + subnet for the ZAP VM (we skipped the default network).

resource "google_compute_network" "vpc" {
  project                 = google_project.zap.project_id
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "subnet" {
  project       = google_project.zap.project_id
  name          = "${var.prefix}-subnet"
  ip_cidr_range = "10.30.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Allow the ZAP API port from the approved source ranges only.
resource "google_compute_firewall" "allow_zap" {
  project       = google_project.zap.project_id
  name          = "${var.prefix}-allow-zap"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = var.allowed_source_ranges
  target_tags   = ["${var.prefix}-server"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.zap_port)]
  }
}

# Optional: SSH from Google IAP's TCP-forwarding range (for admin/debug).
resource "google_compute_firewall" "allow_iap_ssh" {
  count = var.enable_iap_ssh ? 1 : 0

  project       = google_project.zap.project_id
  name          = "${var.prefix}-allow-iap-ssh"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"] # Google IAP TCP forwarding
  target_tags   = ["${var.prefix}-server"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
