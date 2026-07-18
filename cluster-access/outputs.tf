output "attendee_role_grants" {
  description = "Map of attendee (firstlast) -> roles granted on their project."
  value       = { for a in keys(local.attendee_emails) : a => var.attendee_roles }
}
