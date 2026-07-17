# In-cluster resources, applied ONE ATTENDEE PER WORKSPACE.
#
# The kubernetes/helm providers can't be instantiated per-cluster with
# for_each, so we target a single cluster per apply and use the workspace name
# to pick which attendee's cluster that is:
#
#   tofu workspace select -or-create alice   # (terraform: workspace new/select)
#   tofu apply
#
# Loop over everyone with a shell for-loop — see README.md.

data "terraform_remote_state" "clusters" {
  backend = "local"

  config = {
    path = "../kubernetes/terraform.tfstate"
  }
}

locals {
  clusters  = data.terraform_remote_state.clusters.outputs
  attendees = local.clusters.attendees

  # The current workspace selects the target attendee/cluster.
  attendee = terraform.workspace
  valid    = contains(local.attendees, local.attendee)

  # Guarded lookups so a wrong workspace fails via the check block below
  # with a friendly message rather than a raw "key not found" error.
  endpoint = local.valid ? local.clusters.cluster_endpoints[local.attendee] : ""
  ca_cert  = local.valid ? local.clusters.cluster_ca_certificates[local.attendee] : ""
}

# Fail fast (and clearly) if you forgot to select an attendee workspace.
check "workspace_is_attendee" {
  assert {
    condition     = local.valid
    error_message = "Workspace '${local.attendee}' is not a known attendee. Run: tofu workspace select -or-create <attendee> (one of: ${join(", ", local.attendees)})."
  }
}
