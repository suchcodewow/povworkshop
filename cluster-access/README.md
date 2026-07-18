# Cluster access (attendee GKE-admin IAM)

Grants each attendee the IAM they need to manage **their own** GKE cluster —
by default `roles/container.admin` (Kubernetes Engine Admin). This is a separate
layer with its own state, so attendee cluster permissions can be applied and
revoked independently of the projects factory and the clusters themselves.

## Why this exists

`roles/editor` (the attendee's base role) does **not** include
`container.clusterRoleBindings.create`, so attendees can't apply manifests that
create cluster-scoped RBAC (e.g. the Harness delegate's `ClusterRoleBinding`) —
GKE returns `Forbidden`. Kubernetes Engine Admin includes that permission.

## How it works

It reads the attendee → project and attendee → email maps straight from the
[`projects/`](../projects/) factory's state (see [`data.tf`](data.tf)) — the
same way [`addons/`](../addons/) reads the clusters layer. No inputs needed;
apply the projects factory first.

## Usage

```sh
cd cluster-access
tofu init && tofu apply       # or terraform ...
```

Or via the orchestrator (runs after projects, before clusters):

```sh
python3 workshop.py      # -> "Cluster access" -> plan & apply
```

Add more roles by setting `attendee_roles` in a `terraform.tfvars`.
