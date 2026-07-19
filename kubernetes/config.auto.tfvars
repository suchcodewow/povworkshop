# Non-secret config for the clusters layer. Committed and auto-loaded, so a
# fresh clone needs no local tfvars.
#
# attendee_projects is intentionally unset — it's auto-populated from the
# projects/ factory state (see data.tf).

region = "us-central1"
zone   = "us-central1-a"
prefix = "k8s"

# Workshop-friendly sizing.
preemptible    = true
machine_type   = "e2-standard-4"
node_count     = 1
max_node_count = 2

# Nodes are private, so Cloud NAT is what gives pods internet. Leave true so the
# baseline cluster works; the addons/ egress firewall is the thing that takes
# internet away. Set false for an internet-isolated cluster without addons.
enable_nat = true
