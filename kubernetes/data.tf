# Auto-wire the attendee -> project map from the projects/ factory layer.
#
# Leave var.attendee_projects empty ({}) and this reads that layer's
# `attendee_projects` output directly from its state — no copy/paste. Set
# var.attendee_projects explicitly (e.g. projects created outside the factory)
# and this data source is skipped (count = 0) so it won't require that state.
#
# If you move the projects/ layer to a remote (GCS) backend, mirror it here:
#   backend = "gcs"
#   config = {
#     bucket = "my-tf-state-bucket"
#     prefix = "gke/projects"
#   }
data "terraform_remote_state" "projects" {
  count = length(var.attendee_projects) == 0 ? 1 : 0

  backend = "local"
  config = {
    path = "${path.module}/../projects/terraform.tfstate"
  }
}
