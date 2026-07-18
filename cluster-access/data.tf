# Read the projects factory's state for the attendee -> project and
# attendee -> email maps. Same pattern the addons/ layer uses for clusters
# state. Default assumes the projects layer uses LOCAL state.
#
# If the projects layer uses the GCS backend, replace this with:
#   backend = "gcs"
#   config  = { bucket = "my-tf-state-bucket", prefix = "gke/projects" }
data "terraform_remote_state" "projects" {
  backend = "local"

  config = {
    path = "${path.module}/../projects/terraform.tfstate"
  }
}

locals {
  # firstlast -> project ID, and firstlast -> email.
  attendee_projects = data.terraform_remote_state.projects.outputs.attendee_projects
  attendee_emails   = data.terraform_remote_state.projects.outputs.attendee_emails
}
