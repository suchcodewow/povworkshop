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

  # Standalone layer with its OWN state — built/destroyed independently of the
  # attendee projects. Recommended for team use: store state remotely.
  # backend "gcs" {
  #   bucket = "my-tf-state-bucket"
  #   prefix = "zap"
  # }
}
