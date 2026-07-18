# Per-Attendee GKE Clusters on GCP with Terraform / OpenTofu

Provisions **one GKE cluster per workshop attendee**, each in that attendee's
**own GCP project**, from a single config: you map each attendee to a project,
run one `apply`, and each gets a fully isolated, VPC-native zonal cluster. One
`destroy` tears them all down.

Per-project isolation means each attendee has their own network, quotas, IAM,
Binary Authorization policy, and registry — no cross-attendee interference.
This layer provisions *into* existing projects. To have Terraform **create**
the projects too (billing + APIs), run the [`projects/`](projects/) factory
layer first (intended for IT); this layer then reads its `attendee_projects`
output automatically from that layer's state (via [`data.tf`](kubernetes/data.tf)) — no
copy/paste.

The configuration works with either **Terraform** or **OpenTofu** — the
commands below show both. Pick one and use it consistently (don't mix state).

## What gets created

Per attendee, in that attendee's project:

- A dedicated VPC + subnet (with secondary ranges for pods/services)
- A zonal GKE cluster
- A dedicated node service account (least-privilege)
- An autoscaling node pool (auto-repair + auto-upgrade) on spot VMs
- An Artifact Registry (Docker) repo, readable only by that attendee's nodes
- Workload Identity for secure pod → GCP API access

## Secrets & running on a new machine

All sensitive values — the Harness token, GCP billing account, parent org/folder,
and attendee emails — live in **GCP Secret Manager** in a central *operator*
project, never in the repo. [`workshop.py`](workshop.py) loads them into the
environment on startup (as `HARNESS_*` / `TF_VAR_*`), so every layer runs
without you typing anything in. Non-secret config (region, prefix, machine
types) is just committed defaults.

The single credential you carry is your **GCP login** — everything else,
including the Harness token, sits behind it.

**First-time setup (type each value exactly once, ever):**

1. Pick/create a central operator project and set it in
   [`workshop.config.json`](workshop.config.json) (`operator_project`) — or
   export `WORKSHOP_OPERATOR_PROJECT`.
2. `cp secrets.local.env.example secrets.local.env` and fill in the values.
3. Run `python3 workshop.py` → **Manage secrets** — this enables the Secret
   Manager API and pushes each value up (via stdin, so it never hits argv).
4. **Delete `secrets.local.env`** (it's gitignored, but delete it anyway).

**On any machine afterward:**

```sh
git clone <repo> && cd workshop
gcloud auth login && gcloud auth application-default login
python3 workshop.py        # loads secrets from Secret Manager, then runs any layer
```

The mapping of env var → secret name lives in
[`workshop.config.json`](workshop.config.json); a value already exported in your
shell overrides the stored one, and Terraform reads list-typed vars (e.g.
`TF_VAR_attendee_emails`) from the env as HCL/JSON.

## Service-account impersonation (avoids reauth)

User logins are subject to the org's reauthentication policy, so long or
unattended runs can fail mid-plan with `invalid_grant / invalid_rapt`. Service
accounts aren't subject to that policy. Point the workshop at an operator SA and
`workshop.py` impersonates it for **both** Terraform (the `google` provider) and
gcloud — no provider edits, no org-policy change.

**One-time setup** (run as a user with the rights to create the SA and grant
org/folder roles):

```sh
OP_PROJECT=administration-459416          # the operator project (holds secrets)
SA=workshop-operator@$OP_PROJECT.iam.gserviceaccount.com
PARENT=organizations/805624170808         # your org (or folders/<id>)

# 1. Create the operator SA
gcloud iam service-accounts create workshop-operator \
  --project "$OP_PROJECT" --display-name "Workshop operator"

# 2. Let YOUR user mint tokens for it (this is what enables impersonation)
gcloud iam service-accounts add-iam-policy-binding "$SA" \
  --project "$OP_PROJECT" \
  --member "user:$(gcloud config get-value account)" \
  --role roles/iam.serviceAccountTokenCreator

# 3. Grant the SA what the layers need at the org/folder level
for ROLE in roles/resourcemanager.projectCreator roles/billing.user \
            roles/resourcemanager.projectIamAdmin roles/serviceusage.serviceUsageAdmin; do
  gcloud organizations add-iam-policy-binding "${PARENT#organizations/}" \
    --member "serviceAccount:$SA" --role "$ROLE"
done
# 4. Let the SA read the workshop secrets
gcloud projects add-iam-policy-binding "$OP_PROJECT" \
  --member "serviceAccount:$SA" --role roles/secretmanager.secretAccessor
```

Then set it once in [`workshop.config.json`](workshop.config.json)
(`"operator_service_account": "<SA email>"`) or export
`WORKSHOP_IMPERSONATE_SA`. On the next run you'll see `(impersonating service
account: …)` and no more reauth prompts. Leave it empty to use your own ADC.

> The SA impersonates for GCP only. The Harness layer uses the Harness provider
> (its own token), so it's unaffected.

## Prerequisites

1. Install either [Terraform](https://developer.hashicorp.com/terraform/install) (>= 1.5)
   or [OpenTofu](https://opentofu.org/docs/intro/install/) (>= 1.6),
   plus the [gcloud CLI](https://cloud.google.com/sdk/docs/install).
   (None of these are currently installed on this machine.)
1. The attendee projects already exist, have **billing linked**, and your
   identity has (at least) `roles/owner` or the equivalent create/IAM
   permissions in each. (Or create them with the [`projects/`](projects/)
   factory layer, which also handles billing and step 3's APIs for you.)
2. Authenticate for the provider:
   ```sh
   gcloud auth application-default login
   ```
3. Enable the required APIs in **every attendee project**. For example:
   ```sh
   for p in ws-alice-1234 ws-bob-5678 ws-carol-9012; do
     gcloud services enable \
       container.googleapis.com \
       compute.googleapis.com \
       artifactregistry.googleapis.com \
       binaryauthorization.googleapis.com \
       --project "$p"
   done
   ```
4. **Check quotas** in each project/region. Per attendee you need
   `node_count × machine vCPUs` of CPU quota plus in-use IP addresses. New
   projects start with modest defaults — request increases ahead of time
   (Compute Engine API → CPUs / In-use IP addresses).

## Configure attendees

If you created the projects with the [`projects/`](projects/) factory layer,
you don't configure attendees here at all — this layer reads its
`attendee_projects` output straight from that layer's state (via
[`data.tf`](kubernetes/data.tf)). Just leave `attendee_projects` unset and apply.

The clusters layer lives in [`kubernetes/`](kubernetes/) — run its commands from
there:

```sh
cd kubernetes
cp terraform.tfvars.example terraform.tfvars   # set region/zone/prefix; leave attendee_projects unset
```

To use projects created **outside** the factory instead, set the map explicitly
(this overrides the auto-wire — one cluster per entry, in the mapped project):

```hcl
attendee_projects = {
  alice = "ws-alice-1234"   # key: lowercase/numbers/hyphens; value: project ID
  bob   = "ws-bob-5678"
}
```

## Usage

```sh
cd kubernetes

# Terraform
terraform init && terraform plan && terraform apply

# ...or OpenTofu
tofu init && tofu plan && tofu apply
```

## Connect kubectl (hand these out to attendees)

The apply prints a `get_credentials_commands` map — one command per attendee.
View it any time from the clusters layer:

```sh
cd kubernetes
terraform output get_credentials_commands   # or: tofu output ...
```

Each attendee runs their line, then:

```sh
kubectl get nodes
```

## Push images to an attendee's registry

Each attendee has an Artifact Registry repo (matching the Binary Authorization
allowlist, so images from it are admitted). Get the paths from the clusters layer:

```sh
cd kubernetes
terraform output artifact_registry_repos   # or: tofu output ...
```

Then, for one attendee:

```sh
gcloud auth configure-docker us-central1-docker.pkg.dev   # once, matches your region
REPO=$(terraform output -json artifact_registry_repos | jq -r '.alice')
docker tag my-image:latest "$REPO/my-image:latest"
docker push "$REPO/my-image:latest"
```

## Applying additional Terraform during the workshop

Extra Terraform that targets the running clusters lives in **separate layers**,
each with its own state, reading this layer's outputs via
`terraform_remote_state`. Apply them repeatedly mid-workshop without ever
re-planning the clusters. There are two, depending on where the change lives:

**GCP-level changes** ([`addons/`](addons/)) — `google`-provider resources that
`for_each` over all attendees in a single apply:

```sh
cd addons
terraform init && terraform apply   # or: tofu ...
```

Included here:
- `addons/firewall.tf` — denies internet egress for every attendee's nodes
  (keeping internal + Google API traffic working).
- `addons/binauthz.tf` — a Binary Authorization policy **per attendee project**
  that only admits images from that project's allowlisted registries; all other
  images are blocked at admission (never pulled).

See [`addons/README.md`](addons/README.md).

**In-cluster changes** ([`k8s-addons/`](k8s-addons/)) — `kubernetes`-provider
resources (namespaces, RBAC, NetworkPolicies). Because that provider can't be
`for_each`ed per-cluster, this layer uses **one workspace per attendee**:

```sh
cd k8s-addons
tofu init
tofu workspace select -or-create alice && tofu apply   # repeat per attendee
```

See [`k8s-addons/README.md`](k8s-addons/README.md) for the loop-over-everyone
recipe.

## Tear down

Tear down in reverse order — addons first, then clusters:

```sh
cd k8s-addons && for a in alice bob carol; do tofu workspace select "$a" && tofu destroy -auto-approve; done && cd ..
cd addons && terraform destroy && cd ..           # remove GCP-level addons
cd kubernetes && terraform destroy && cd ..       # remove all clusters + network
```

To remove a single attendee, delete their name from `attendees` and re-apply.

## Notes

- **State**: with multiple clusters in one state file, use a remote backend so
  the state is shared and locked — uncomment the GCS backend in `versions.tf`
  and point it at a bucket. Avoid concurrent applies against the same state.
- **Scale**: the CIDR layout in `network.tf` supports up to ~100 attendees.
  Beyond that, widen the ranges.
- **Cost**: defaults use spot VMs (`preemptible = true`) and a small
  `machine_type`. Cost scales with the number of attendees — remember to
  `destroy` promptly when the workshop ends.
