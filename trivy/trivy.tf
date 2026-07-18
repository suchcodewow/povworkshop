# Static IP so the endpoint attendees are given stays stable across VM restarts.
resource "google_compute_address" "trivy" {
  project = google_project.trivy.project_id
  name    = "${var.prefix}-ip"
  region  = var.region

  depends_on = [google_project_service.compute]
}

locals {
  # Container-Optimized OS runs the container declared here. Trivy runs in
  # `server` mode holding the shared vulnerability DB, so attendee clients need
  # no internet DB download. This project has unrestricted egress, so the VM can
  # pull the image and refresh the DB itself.
  container_declaration = yamlencode({
    spec = {
      containers = [{
        name  = "trivy"
        image = var.trivy_image
        args  = ["server", "--listen", "0.0.0.0:${var.trivy_port}"]
      }]
      restartPolicy = "Always"
    }
  })
}

resource "google_compute_instance" "trivy" {
  project      = google_project.trivy.project_id
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
      nat_ip = google_compute_address.trivy.address
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

  # Default compute service account with cloud-platform scope (enough to write
  # logs); actual access is still governed by that SA's IAM roles.
  service_account {
    scopes = ["cloud-platform"]
  }

  depends_on = [google_project_service.compute]
}
