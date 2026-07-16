# projects — attendee project factory (run by IT, first)

Creates one GCP **project per attendee**, links billing, and enables the APIs
the clusters layer needs. This is a **standalone layer with its own state**,
meant to be run once up front by someone with the org/billing permissions.

Its output, `attendee_projects`, is the map the clusters layer consumes — so
the flow is: run this → copy the output → paste into `../terraform.tfvars` →
apply the clusters layer.

## Who runs this / permissions

The identity running this needs, on the target **folder** and **billing account**:

- `roles/resourcemanager.projectCreator` on the folder
- `roles/billing.user` (and `billing.resourceAssociations.create`) on the
  billing account

These are exactly the elevated permissions you *don't* want to hand to everyone
— hence a separate layer.

## Usage

```sh
cd projects
cp terraform.tfvars.example terraform.tfvars   # set folder_id, billing_account, attendees
tofu init && tofu apply                         # or terraform ...
```

## Wire it into the clusters layer

```sh
# Print the block to paste:
tofu output -raw attendee_projects_tfvars
```

Copy that `attendee_projects = { ... }` block into `../terraform.tfvars`, then
apply the clusters layer as usual. (Alternatively, read this layer's state via
`terraform_remote_state` from the clusters layer — but copy/paste keeps the two
loosely coupled and lets you edit IDs by hand.)

## What gets created

- `google_project` per attendee — `<prefix>-<attendee>-<random>` (the random
  suffix keeps the globally-unique project ID from colliding), under `folder_id`,
  billed to `billing_account`, with the default network disabled.
- `google_project_service` — each API in `var.apis` enabled in each project.

## Tear down

Projects are **protected**: `deletion_policy = "PREVENT"` means `tofu destroy`
(or removing an attendee) will **error** rather than delete a project — a
guardrail against wiping attendee environments by accident.

To intentionally remove a project, either delete it manually in the console /
`gcloud projects delete <id>`, or temporarily switch `deletion_policy` to
`"DELETE"` in `main.tf`, `apply`, then `destroy`.
