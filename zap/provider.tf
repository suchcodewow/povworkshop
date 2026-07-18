# No default project — the created project's ID is set per-resource. Credentials
# come from ADC (gcloud auth application-default login).
provider "google" {
  region = var.region
}
