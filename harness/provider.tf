# Harness Platform (NextGen) provider. When account_id / platform_api_key are
# left null, the provider falls back to the HARNESS_ACCOUNT_ID and
# HARNESS_PLATFORM_API_KEY environment variables — the preferred way to pass the
# token so it never lands in a tfvars file or state input.
provider "harness" {
  endpoint         = var.endpoint
  account_id       = var.account_id
  platform_api_key = var.platform_api_key
}
