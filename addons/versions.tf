terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # This layer has its OWN state, separate from the clusters layer.
  # If the clusters layer uses the GCS backend, use one here too (different
  # prefix) and update data.tf to read from GCS instead of local.
  # backend "gcs" {
  #   bucket = "my-tf-state-bucket"
  #   prefix = "gke/addons"
  # }
}
