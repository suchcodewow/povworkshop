# Non-secret config for the standalone Trivy layer. Committed and auto-loaded.
#
# parent / billing_account come from Secret Manager via workshop.py.

region = "us-central1"
zone   = "us-central1-a"
prefix = "trivy"

trivy_port  = 4954
preemptible = false

# Public source IPs allowed to reach the Trivy server port. Replace with the
# real IPs attendees connect from before applying.
allowed_source_ranges = [
  "198.51.100.7/32",
]
