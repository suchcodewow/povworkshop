terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }

  # One workspace per attendee keeps in-cluster state isolated per cluster.
  # If you use the GCS backend, each workspace gets its own state object
  # automatically under this prefix.
  # backend "gcs" {
  #   bucket = "my-tf-state-bucket"
  #   prefix = "gke/k8s-addons"
  # }
}
