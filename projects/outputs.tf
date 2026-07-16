output "attendee_projects" {
  description = "Map of attendee -> created project ID."
  value       = { for a, p in google_project.attendee : a => p.project_id }
}

# Ready-to-paste block for the clusters layer's terraform.tfvars.
output "attendee_projects_tfvars" {
  description = "Paste this into ../terraform.tfvars for the clusters layer."
  value = join("\n", concat(
    ["attendee_projects = {"],
    [for a, p in google_project.attendee : "  ${a} = \"${p.project_id}\""],
    ["}"],
  ))
}
