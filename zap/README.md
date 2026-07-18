# OWASP ZAP shared-scanner project

A **standalone** GCP project that hosts an [OWASP ZAP](https://www.zaproxy.org)
**daemon** for attendees to run DAST scans during the workshop. Same shape as
[`../trivy/`](../trivy/): its own Terraform state, built and destroyed
independently of the attendee projects (`deletion_policy = "DELETE"`).

## What gets created

- A dedicated GCP project (`<prefix>-<6 hex>`), billing linked, Compute API on.
- A minimal VPC + subnet.
- A Container-Optimized OS VM running `ghcr.io/zaproxy/zaproxy:stable` in
  **daemon mode** (`zap.sh -daemon`) exposing the ZAP API on port 8080, with a
  **static public IP** and an **API key**.
- A firewall rule allowing the ZAP port **only** from `allowed_source_ranges`
  (plus optional SSH from Google IAP's range).

## Why a daemon (vs one-shot scans)

Running one persistent ZAP daemon mirrors the central-Trivy-server model:
attendees point a ZAP client / API calls at this shared endpoint to spider and
active-scan their app's URL, instead of each running a full ZAP locally. The VM
has unrestricted egress, so ZAP can reach public scan targets and refresh
add-ons.

## Prerequisites

- Terraform (>= 1.5) / OpenTofu, gcloud, and `gcloud auth application-default login`.
- `parent` and `billing_account` — provided automatically from Secret Manager
  when run via [`../workshop.py`](../workshop.py); otherwise set them in
  `terraform.tfvars`.

## Usage

```sh
cd zap
cp terraform.tfvars.example terraform.tfvars   # set allowed_source_ranges
tofu init && tofu apply       # or terraform ...
```

Or via the orchestrator (loads parent/billing from Secret Manager):

```sh
python3 workshop.py      # -> "OWASP ZAP" -> plan & apply   (a standalone layer)
```

## How attendees use it

Give attendees the endpoint and API key, then they drive scans from an allowed
source IP (laptop / Cloud Shell) — via the ZAP API, `zap-cli`, or the ZAP
desktop connected to this daemon:

```sh
tofu output zap_endpoint            # http://<IP>:8080
tofu output -raw zap_api_key        # the API key (sensitive)

# Confirm the daemon is up:
curl "http://<IP>:8080/JSON/core/view/version/?apikey=<KEY>"

# Example: spider then active-scan a target app URL
curl "http://<IP>:8080/JSON/spider/action/scan/?apikey=<KEY>&url=https://my-app.example.com"
curl "http://<IP>:8080/JSON/ascan/action/scan/?apikey=<KEY>&url=https://my-app.example.com"
```

## Security notes

- ZAP takes ~30–60s to start (JVM + add-ons) after the VM boots; the API 404s
  or refuses connections until then.
- A reachable ZAP daemon can be instructed to scan/proxy **arbitrary** targets,
  so keep `allowed_source_ranges` tight and treat the API key as a secret
  (`zap_api_key` output is marked sensitive; it's injected into VM metadata).
- The scan **target** must be reachable from the ZAP VM (public URL). Attendee
  in-cluster apps need a public ingress/LoadBalancer for ZAP to reach them.
