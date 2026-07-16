terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Recommended for IT/shared use — store state remotely.
  # backend "gcs" {
  #   bucket = "my-tf-state-bucket"
  #   prefix = "gke/projects"
  # }
}

# No default project needed to create projects; credentials come from ADC.
provider "google" {}
