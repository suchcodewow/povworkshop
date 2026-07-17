output "org_identifier" {
  description = "Identifier of the workshop organization (use as org_id for org-scoped resources)."
  value       = harness_platform_organization.workshop.identifier
}

output "org_id" {
  description = "Resource ID of the workshop organization."
  value       = harness_platform_organization.workshop.id
}

output "attendee_projects" {
  description = "Map of attendee (firstlast) -> Harness project identifier/name."
  value       = { for k, p in harness_platform_project.attendee : k => { identifier = p.identifier, name = p.name } }
}
