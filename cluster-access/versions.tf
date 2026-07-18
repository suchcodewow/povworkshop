terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Its own state, separate from the projects factory. If the projects layer
  # uses the GCS backend, use one here too and update data.tf to read from GCS.
  # backend "gcs" {
  #   bucket = "my-tf-state-bucket"
  #   prefix = "cluster-access"
  # }
}
