variable "account_id" {
  description = <<-EOT
    Harness account identifier. Leave null to read from the HARNESS_ACCOUNT_ID
    environment variable instead.
  EOT
  type        = string
  default     = null
}

variable "platform_api_key" {
  description = <<-EOT
    Harness Platform API key/token (NextGen), e.g. "pat.xxxx..." or "sat.xxxx...".
    Sensitive — prefer exporting HARNESS_PLATFORM_API_KEY and leaving this null,
    so the token never enters a tfvars file or the state.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "endpoint" {
  description = "Harness API endpoint. Default is the SaaS gateway; override for self-managed/other clusters (e.g. https://app.harness.io/gateway)."
  type        = string
  default     = "https://app.harness.io/gateway"
}

variable "org_identifier" {
  description = <<-EOT
    Unique (lowercase) identifier for the workshop organization. Leave null to
    let workshop.py derive it from the current month as "<month>_int" (e.g.
    "july_int"); set a string to override. Must start with a lowercase letter or
    underscore and contain only lowercase letters, digits, and underscores
    (no hyphens or spaces), <= 128 chars.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.org_identifier == null || can(regex("^[a-z_][0-9a-z_]{0,127}$", var.org_identifier))
    error_message = "org_identifier must be lowercase: start with a letter/underscore and contain only lowercase letters, digits, and underscores (<= 128 chars)."
  }
}

variable "org_name" {
  description = <<-EOT
    Display name for the workshop organization. Leave null to auto-generate as
    "<current month>_INT" (e.g. "July_INT"); set a string to override.
  EOT
  type        = string
  default     = null
}

variable "org_description" {
  description = "Description for the workshop organization."
  type        = string
  default     = "Organization for the workshop."
}

variable "org_tags" {
  description = "Tags applied to the organization, each formatted as \"key:value\"."
  type        = list(string)
  default     = ["purpose:workshop"]
}
