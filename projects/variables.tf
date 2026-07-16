variable "attendees" {
  description = <<-EOT
    List of attendee identifiers, one project per attendee. Each must be a
    valid name fragment: lowercase letters, numbers, and hyphens. Keep them
    short — the generated project_id (prefix-attendee-suffix) must be <= 30 chars.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.attendees) > 0
    error_message = "Provide at least one attendee."
  }
}

variable "folder_id" {
  description = "Folder to create the projects under. Numeric ID (e.g. \"123456789\") or \"folders/123456789\"."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID to link (e.g. \"0123AB-4567CD-89EF01\")."
  type        = string
}

variable "prefix" {
  description = "Name prefix for the projects. Keep the total project_id <= 30 chars."
  type        = string
  default     = "workshop"
}

variable "apis" {
  description = "APIs enabled in every attendee project (required by the clusters layer)."
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "binaryauthorization.googleapis.com",
  ]
}
