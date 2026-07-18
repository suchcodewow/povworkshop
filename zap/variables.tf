variable "parent" {
  description = <<-EOT
    Parent for the created project: "organizations/<id>" or "folders/<id>".
    Normally supplied via TF_VAR_parent from Secret Manager (same value the
    projects/ layer uses).
  EOT
  type        = string

  validation {
    condition     = can(regex("^(organizations|folders)/[0-9]+$", var.parent))
    error_message = "parent must be \"organizations/<numeric id>\" or \"folders/<numeric id>\"."
  }
}

variable "billing_account" {
  description = "Billing account ID to link (e.g. \"0123AB-4567CD-89EF01\"). Normally supplied via TF_VAR_billing_account from Secret Manager."
  type        = string
}

variable "prefix" {
  description = "Name prefix for the project and its resources. project_id is <prefix>-<6 hex>."
  type        = string
  default     = "zap"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,20}$", var.prefix))
    error_message = "prefix must start with a lowercase letter, contain only lowercase letters/digits/hyphens, and be <= 21 chars."
  }
}

variable "region" {
  description = "GCP region for the subnet, static IP, and VM."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the VM. Must be within var.region."
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "Machine type for the ZAP server VM. ZAP is Java-based and memory-hungry; e2-medium (4 GB) is a sane minimum."
  type        = string
  default     = "e2-medium"
}

variable "preemptible" {
  description = "Use a spot/preemptible VM. Default false so the shared scanner stays up for the whole workshop."
  type        = bool
  default     = false
}

variable "zap_image" {
  description = "ZAP container image. Official GHCR image (no Docker Hub rate limits)."
  type        = string
  default     = "ghcr.io/zaproxy/zaproxy:stable"
}

variable "zap_port" {
  description = "TCP port the ZAP daemon/API listens on (ZAP's default is 8080)."
  type        = number
  default     = 8080
}

variable "zap_api_key" {
  description = <<-EOT
    API key required to call the ZAP API. Leave null to auto-generate a random
    key (surfaced via the zap_api_key output). Sensitive — it's injected into VM
    metadata to start the daemon.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "allowed_source_ranges" {
  description = <<-EOT
    CIDRs allowed to reach the ZAP API port. Restrict to the PUBLIC source IPs
    attendees connect from (laptop IPs, Cloud Shell egress, a NAT IP).

    IMPORTANT: a reachable ZAP daemon can be told to scan/proxy arbitrary targets,
    so keep this tight. Use ["0.0.0.0/0"] only for a fully-open, short-lived
    workshop.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.allowed_source_ranges) > 0
    error_message = "Set at least one CIDR in allowed_source_ranges (or [\"0.0.0.0/0\"] to open it fully)."
  }
}

variable "enable_iap_ssh" {
  description = "Allow SSH to the VM from Google IAP's TCP-forwarding range (for admin/debug)."
  type        = bool
  default     = true
}
