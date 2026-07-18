# Trivy shared-scanner project

A **standalone** GCP project that hosts an [Aqua Trivy](https://trivy.dev)
**server** for attendees to use during the workshop. It has its own Terraform
state, so it's built and destroyed independently of the attendee projects
(`deletion_policy = "DELETE"`, so `destroy` removes the project).

## What gets created

- A dedicated GCP project (`<prefix>-<6 hex>`), billing linked, Compute API on.
- A minimal VPC + subnet.
- A Container-Optimized OS VM running `trivy server` (the official
  `aquasec/trivy` image) on port 4954, with a **static public IP**.
- A firewall rule allowing the Trivy port **only** from `allowed_source_ranges`
  (plus optional SSH from Google IAP's range).

## Why server mode

Attendee clusters have **restricted egress** (see [`addons/`](../addons/)), so
each attendee downloading Trivy's ~1 GB vulnerability DB won't work. Running one
central `trivy server` holds the DB in a single place; clients just send the
image reference and get results back — no per-client DB download.

## Prerequisites

- Terraform (>= 1.5) / OpenTofu, gcloud, and `gcloud auth application-default login`.
- `parent` and `billing_account` — provided automatically from Secret Manager
  when run via [`../workshop.py`](../workshop.py); otherwise set them in
  `terraform.tfvars`.

## Usage

```sh
cd trivy
cp terraform.tfvars.example terraform.tfvars   # set allowed_source_ranges
tofu init && tofu apply       # or terraform ...
```

Or via the orchestrator (loads parent/billing from Secret Manager):

```sh
python3 workshop.py      # -> "Trivy" -> plan & apply   (a standalone layer)
```

## How attendees use it

Give attendees the endpoint from the output, then they run the Trivy **client**
from their **laptop or Cloud Shell** (not from inside the restricted cluster):

```sh
tofu output trivy_client_example
# trivy image --server http://<IP>:4954 <IMAGE>
```

## Access note

`allowed_source_ranges` must list the public IPs attendees connect from. Because
attendee GKE nodes can't reach public IPs (restricted egress), running the
client from inside a cluster won't work unless you also open egress to this IP
in [`../addons/firewall.tf`](../addons/firewall.tf). For most workshops, having
attendees run the client from their laptop/Cloud Shell is simplest.
