# Read the clusters layer's state to discover attendees, the network, and the
# per-attendee node tags — no need to redeclare any of it here.
#
# Default assumes the clusters layer uses LOCAL state (../terraform.tfstate).
# If it uses the GCS backend, replace the block below with:
#
#   data "terraform_remote_state" "clusters" {
#     backend = "gcs"
#     config = {
#       bucket = "my-tf-state-bucket"
#       prefix = "gke/state"
#     }
#   }
data "terraform_remote_state" "clusters" {
  backend = "local"

  config = {
    path = "../terraform.tfstate"
  }
}

locals {
  clusters          = data.terraform_remote_state.clusters.outputs
  attendees         = local.clusters.attendees
  prefix            = local.clusters.prefix
  region            = local.clusters.region
  node_tags         = local.clusters.node_tags
  attendee_projects = local.clusters.attendee_projects
  network_names     = local.clusters.network_names
}
