terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Recommended for team use — store state remotely instead of locally.
  # Uncomment and set your bucket after creating it.
  # backend "gcs" {
  #   bucket = "my-tf-state-bucket"
  #   prefix = "gke/state"
  # }
}
