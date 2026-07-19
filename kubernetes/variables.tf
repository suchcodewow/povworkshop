variable "attendee_projects" {
  description = <<-EOT
    Map of attendee identifier -> existing GCP project ID for that attendee.
    One cluster (and its own VPC, registry, node SA) is created in each project.

    Leave this empty ({}, the default) to auto-populate from the projects/
    factory layer's `attendee_projects` output (read via data.tf) — no
    copy/paste needed. Set it explicitly only for projects created outside that
    layer, in which case they must already exist, have billing linked, and have
    the required APIs enabled (see README). The attendee key must be a valid
    resource-name fragment: lowercase letters, numbers, and hyphens.
  EOT
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "The GCP region for the subnets and registries."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for the (zonal) clusters. Must be within var.region."
  type        = string
  default     = "us-central1-a"
}

variable "prefix" {
  description = "Name prefix for resources within each project."
  type        = string
  default     = "workshop"
}

variable "machine_type" {
  description = "Machine type for node pool VMs."
  type        = string
  default     = "e2-standard-4"
}

variable "node_count" {
  description = "Number of nodes per cluster (min for autoscaling)."
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes per cluster for autoscaling."
  type        = number
  default     = 3
}

variable "preemptible" {
  description = "Use spot/preemptible VMs — cheaper and fine for short-lived workshop clusters."
  type        = bool
  default     = true
}

variable "enable_nat" {
  description = <<-EOT
    Create a Cloud NAT so pods on the private nodes can reach the internet.

    Nodes are private (no external IPs), so without NAT they have no route to
    the internet at all. Keep this true so the baseline cluster works normally
    (e.g. a Harness delegate can reach app.harness.io) and the addons/ egress
    firewall is what deliberately takes internet away. Set false to have the
    cluster be internet-isolated on its own.
  EOT
  type        = bool
  default     = true
}
