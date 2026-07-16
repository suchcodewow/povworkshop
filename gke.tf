# One zonal GKE cluster per attendee, each with a separately-managed node pool.
# Zonal (single control plane) + spot VMs keeps short-lived workshop clusters
# cheap and fast to create.

resource "google_container_cluster" "primary" {
  for_each = toset(local.attendees)

  project  = var.attendee_projects[each.key]
  name     = "${var.prefix}-${each.key}"
  location = var.zone

  # Manage node pools separately, so remove the default one.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc[each.key].id
  subnetwork = google_compute_subnetwork.subnet[each.key].id

  # VPC-native cluster using the subnet's secondary ranges.
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Workload Identity — the recommended way for pods to access GCP APIs.
  workload_identity_config {
    workload_pool = "${var.attendee_projects[each.key]}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  # Enforce this project's Binary Authorization image policy (defined in
  # ../addons/binauthz.tf). Until that policy is applied, the project default
  # is permissive, so clusters keep working.
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Workshop clusters are disposable — allow clean `destroy`.
  deletion_protection = false
}

resource "google_container_node_pool" "primary_nodes" {
  for_each = toset(local.attendees)

  project  = var.attendee_projects[each.key]
  name     = "${var.prefix}-${each.key}-pool"
  location = var.zone
  cluster  = google_container_cluster.primary[each.key].name

  node_count = var.node_count

  autoscaling {
    min_node_count = var.node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.machine_type
    preemptible  = var.preemptible

    # Run nodes as this attendee's dedicated service account (see
    # service_accounts.tf). With cloud-platform scope, actual access is
    # governed by the IAM roles granted to that SA.
    service_account = google_service_account.node[each.key].email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      env      = "workshop"
      attendee = each.key
    }

    # Network tag used by the addon layer to scope per-attendee firewall rules.
    tags = ["${var.prefix}-node", "${var.prefix}-${each.key}"]
  }
}
