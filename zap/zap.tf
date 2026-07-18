# Auto-generate an API key when one isn't supplied.
resource "random_password" "api_key" {
  count   = var.zap_api_key == null ? 1 : 0
  length  = 32
  special = false
}

# Static IP so the endpoint attendees are given stays stable across restarts.
resource "google_compute_address" "zap" {
  project = google_project.zap.project_id
  name    = "${var.prefix}-ip"
  region  = var.region

  depends_on = [google_project_service.compute]
}

locals {
  api_key = coalesce(var.zap_api_key, try(random_password.api_key[0].result, ""))

  # Container-Optimized OS runs the container declared here: ZAP in daemon mode
  # exposing its API on the configured port. api.addrs.* opens the API to remote
  # callers; api.key requires the key on every request. This project has
  # unrestricted egress so ZAP can reach public scan targets and refresh add-ons.
  container_declaration = yamlencode({
    spec = {
      containers = [{
        name    = "zap"
        image   = var.zap_image
        command = ["zap.sh"]
        args = [
          "-daemon",
          "-host", "0.0.0.0",
          "-port", tostring(var.zap_port),
          "-config", "api.addrs.addr.name=.*",
          "-config", "api.addrs.addr.regex=true",
          "-config", "api.key=${local.api_key}",
        ]
      }]
      restartPolicy = "Always"
    }
  })
}

resource "google_compute_instance" "zap" {
  project      = google_project.zap.project_id
  name         = "${var.prefix}-server"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["${var.prefix}-server"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {
      nat_ip = google_compute_address.zap.address
    }
  }

  scheduling {
    preemptible        = var.preemptible
    automatic_restart  = !var.preemptible
    provisioning_model = var.preemptible ? "SPOT" : "STANDARD"
  }

  metadata = {
    gce-container-declaration = local.container_declaration
    google-logging-enabled    = "true"
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  depends_on = [google_project_service.compute]
}
