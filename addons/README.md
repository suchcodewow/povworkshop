# Addons — additional Terraform applied to the running clusters

This is a **separate Terraform layer** with its own state. It reads the
clusters layer's outputs via `terraform_remote_state` (see `data.tf`), so it
can target the already-deployed clusters without redeclaring them. Apply it as
many times as you like during the workshop without ever touching cluster state.

## Prerequisite

The clusters layer (the parent directory) must be applied first, so its state
and outputs exist.

## Usage

Run from **inside this directory**:

```sh
cd addons

# Terraform
terraform init && terraform apply

# ...or OpenTofu
tofu init && tofu apply
```

Roll a change back by removing/editing the resource and re-applying, or
`terraform destroy` to remove just the addons (clusters are untouched).

## What's here

- `firewall.tf` — limits internet access for every attendee's cluster nodes
  (deny internet egress; allow internal ranges + Google APIs). Scoped
  per-attendee via the node network tags exported by the clusters layer.
- `binauthz.tf` — a Binary Authorization policy **per attendee project** that
  allowlists image registries; images from anywhere else are denied at pod
  admission, so they're never pulled. Edit the `admission_whitelist_patterns`
  to match your registries. Requires `binaryauthorization.googleapis.com`
  enabled in each project and the `binary_authorization` block on each cluster
  (already set in `../gke.tf`).

## Adding more addons

Drop new `.tf` files here. Anything that operates at the **GCP level** (the
`google` provider) can `for_each` over `local.attendees` and apply to all
clusters in one go, exactly like `firewall.tf`.

For **in-cluster** resources (the `kubernetes`/`helm` providers) note that
those providers can't be created per-cluster with `for_each`. Handle multiple
clusters with one workspace per attendee (a provider configured from a
`cluster` variable), or a per-cluster module with an explicit provider.

## State note

`data.tf` defaults to reading the clusters layer's **local** state at
`../terraform.tfstate`. If you switch the clusters layer to the GCS backend,
update both `data.tf` (the remote_state block) and `versions.tf` (this layer's
own backend) accordingly — see the comments in those files.
