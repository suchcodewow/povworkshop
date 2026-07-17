terraform {
  required_version = ">= 1.5"

  required_providers {
    harness = {
      source  = "harness/harness"
      version = "~> 0.44"
    }
  }

  # Recommended for team use — store state remotely instead of locally.
  # backend "gcs" {
  #   bucket = "my-tf-state-bucket"
  #   prefix = "harness/org"
  # }
}
