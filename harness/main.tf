# The workshop organization. Downstream Harness resources (projects, pipelines,
# connectors) would set org_id = harness_platform_organization.workshop.id.
resource "harness_platform_organization" "workshop" {
  identifier  = var.org_identifier
  name        = var.org_name
  description = var.org_description
  tags        = var.org_tags
}
