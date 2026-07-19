# Non-secret config for the standalone OWASP ZAP layer. Committed and auto-loaded.
#
# parent / billing_account come from Secret Manager via workshop.py.
# zap_api_key is left unset so it's auto-generated (see the zap_api_key output).

region = "us-central1"
zone   = "us-central1-a"
prefix = "zap"

zap_port    = 8080
preemptible = false

# Public source IPs allowed to reach the ZAP API port. A reachable ZAP daemon can
# scan/proxy arbitrary targets — keep this tight and replace before applying.
allowed_source_ranges = [
  "198.51.100.7/32",
]
