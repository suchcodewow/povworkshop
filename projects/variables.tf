variable "attendee_emails" {
  description = <<-EOT
    List of attendee email addresses, one project per attendee. Each local part
    (before the @) must be "first.last"; the project-name fragment is derived by
    joining the name parts together and lowercasing (e.g. Shawn.Pearson@x.com ->
    shawnpearson). Keep names short — the generated project_id
    (prefix-firstlast-suffix) must be <= 30 chars.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.attendee_emails) > 0
    error_message = "Provide at least one attendee email."
  }

  validation {
    condition     = alltrue([for e in var.attendee_emails : can(regex("^[^@]+@[^@]+$", e))])
    error_message = "Each entry must be a valid email address of the form local@domain."
  }
}

variable "shared_editor_emails" {
  description = <<-EOT
    Emails granted roles/editor on EVERY attendee project but given NO project
    of their own (e.g. instructors/operators). Separate from attendee_emails —
    these addresses never create a project, VPC, cluster, or node SA; they only
    receive the cross-project editor grant.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.shared_editor_emails : can(regex("^[^@]+@[^@]+$", e))])
    error_message = "Each entry must be a valid email address of the form local@domain."
  }
}

variable "operator_service_account" {
  description = <<-EOT
    Operator service account email that runs the workshop (via impersonation).
    When set, it's granted roles/owner on EVERY attendee project so the
    impersonated runs can manage their resources (registries, clusters, node SAs
    and IAM) — needed because attendee projects may have been created by a
    different identity. Supplied automatically by workshop.py
    (TF_VAR_operator_service_account) when impersonation is configured; leave
    null to skip the grant.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.operator_service_account == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.operator_service_account))
    error_message = "operator_service_account must be a service account email (…@….iam.gserviceaccount.com)."
  }
}

variable "parent" {
  description = "Parent for the created projects: \"organizations/<id>\" or \"folders/<id>\" (e.g. \"organizations/805624170808\" or \"folders/916995945005\")."
  type        = string

  validation {
    condition     = can(regex("^(organizations|folders)/[0-9]+$", var.parent))
    error_message = "parent must be \"organizations/<numeric id>\" or \"folders/<numeric id>\"."
  }
}

variable "billing_account" {
  description = "Billing account ID to link (e.g. \"0123AB-4567CD-89EF01\")."
  type        = string
}

variable "prefix" {
  description = "Name prefix for the projects. project_id is <prefix>-<firstlast>-<6 hex>; the firstlast fragment is truncated to keep the total <= 30 chars, so a shorter prefix leaves more room for names."
  type        = string
  default     = "workshop"

  # project_id must start with a lowercase letter; also reserve room for the
  # fragment + suffix: len(prefix) <= 30 - 8 - 1 = 21 (at least 1 fragment char).
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,20}$", var.prefix))
    error_message = "prefix must start with a lowercase letter, contain only lowercase letters/digits/hyphens, and be <= 21 chars."
  }
}

variable "attendee_role" {
  description = <<-EOT
    IAM role each attendee is granted on their own project. Defaults to editor,
    which gives full resource control (create/delete/deploy) without IAM/billing
    admin. Note: roles/owner CANNOT be granted to users outside the org's domain
    via Terraform (GCP requires external owners to be invited and accept), so it
    fails with ORG_MUST_INVITE_EXTERNAL_OWNERS for attendees external to the org.
  EOT
  type        = string
  default     = "roles/editor"
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
