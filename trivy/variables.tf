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
  description = <<-EOT
    Billing account ID to link (e.g. "0123AB-4567CD-89EF01"). Normally supplied
    via TF_VAR_billing_account from Secret Manager.
  EOT
  type        = string
}

variable "prefix" {
  description = "Name prefix for the project and its resources. project_id is <prefix>-<6 hex>."
  type        = string
  default     = "trivy"

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
  description = "Machine type for the Trivy server VM. e2-small is plenty for a workshop."
  type        = string
  default     = "e2-small"
}

variable "preemptible" {
  description = <<-EOT
    Use a spot/preemptible VM. Default false so the shared scanner stays up for
    the whole workshop; set true to save cost if occasional restarts are OK.
  EOT
  type        = bool
  default     = false
}

variable "trivy_image" {
  description = "Trivy container image (Docker Hub). Pin a version for reproducibility."
  type        = string
  default     = "aquasec/trivy:latest"
}

variable "trivy_port" {
  description = "TCP port the Trivy server listens on (default 4954, Trivy's standard)."
  type        = number
  default     = 4954
}

variable "allowed_source_ranges" {
  description = <<-EOT
    CIDRs allowed to reach the Trivy server port. Restrict to the PUBLIC source
    IPs attendees connect from (laptop IPs, Cloud Shell egress, a NAT IP).

    NOTE: attendee GKE nodes have restricted egress (addons/firewall.tf) and
    cannot reach a public IP, so attendees should run the Trivy client from their
    laptop/Cloud Shell — not from inside their cluster. Use ["0.0.0.0/0"] only
    for a fully-open, short-lived workshop.
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
