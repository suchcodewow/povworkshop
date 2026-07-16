# k8s-addons — in-cluster Terraform, one workspace per attendee

This layer holds resources that live **inside** the clusters (the `kubernetes`
provider): namespaces, RBAC, NetworkPolicies, etc.

Unlike the GCP-level [`../addons`](../addons) layer (which `for_each`es over all
attendees in one apply), the `kubernetes` provider **cannot** be instantiated
per-cluster with `for_each`. So this layer targets **one cluster per apply**,
and uses the **workspace name** to pick which attendee's cluster:

```
tofu workspace select -or-create alice   # terraform: workspace new/select alice
tofu apply
```

The provider is configured from that attendee's endpoint + CA cert, read out of
the clusters layer's remote state.

## Prerequisites

- The clusters layer (grandparent dir) is applied.
- You're authenticated with an identity that can reach the cluster API:
  ```sh
  gcloud auth application-default login
  ```

## Apply to one attendee

```sh
cd k8s-addons
tofu init
tofu workspace select -or-create alice
tofu apply
```

## Apply to everyone (loop over workspaces)

```sh
cd k8s-addons
tofu init
for a in alice bob carol; do
  tofu workspace select -or-create "$a"
  tofu apply -auto-approve
done
```

> With Terraform instead of OpenTofu, use
> `terraform workspace select "$a" || terraform workspace new "$a"`
> (there's no `-or-create` flag).

## Guardrail

`data.tf` has a `check` block that fails with a clear message if the current
workspace isn't a known attendee — so an accidental apply in the `default`
workspace won't target the wrong cluster.

## Tear down

Per attendee:

```sh
tofu workspace select alice
tofu destroy
```

Or loop the same way as apply.
