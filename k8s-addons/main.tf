# Example in-cluster resource: a per-attendee namespace.
# This applies to whichever cluster the current workspace selects.
resource "kubernetes_namespace" "workshop" {
  metadata {
    name = "workshop"

    labels = {
      "managed-by" = "terraform"
      "attendee"   = local.attendee
    }
  }
}

# Example: a default-deny egress NetworkPolicy (allowing DNS), the in-cluster
# analog of the VPC firewall in ../addons. Uncomment to use.
#
# NOTE: NetworkPolicy is only ENFORCED if the cluster has network policy /
# Dataplane V2 enabled. The workshop clusters don't by default (we restrict
# egress at the VPC layer instead), so this object would be accepted but not
# enforced until you enable it on the cluster.
#
# resource "kubernetes_network_policy" "default_deny_egress" {
#   metadata {
#     name      = "default-deny-egress"
#     namespace = kubernetes_namespace.workshop.metadata[0].name
#   }
#   spec {
#     pod_selector {} # all pods in the namespace
#     policy_types = ["Egress"]
#     egress {
#       # allow DNS only
#       to {}
#       ports {
#         protocol = "UDP"
#         port     = "53"
#       }
#     }
#   }
# }
