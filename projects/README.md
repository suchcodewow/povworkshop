# projects — attendee project factory (run by IT, first)

Creates one GCP **project per attendee**, links billing, and enables the APIs
the clusters layer needs. This is a **standalone layer with its own state**,
meant to be run once up front by someone with the org/billing permissions.

Its output, `attendee_projects`, is the map the clusters layer consumes — and
the clusters layer reads it **automatically** from this layer's state (via
`../data.tf`). So the flow is just: apply this → apply the clusters layer. No
copy/paste (leave the clusters layer's `attendee_projects` var unset).

## Who runs this / permissions

The identity running this needs, on the target **parent** (org or folder) and **billing account**:

- `roles/resourcemanager.projectCreator` on the parent org/folder (may be
  inherited, e.g. granted to `domain:<your-domain>` at the org)
- `roles/billing.user` (and `billing.resourceAssociations.create`) on the
  billing account

These are exactly the elevated permissions you *don't* want to hand to everyone
— hence a separate layer.

## Usage

```sh
cd projects
cp terraform.tfvars.example terraform.tfvars   # set parent, billing_account, attendee_emails
tofu init && tofu apply                         # or terraform ...
```

## Wire it into the clusters layer

Nothing to do — the clusters layer reads this layer's `attendee_projects`
output automatically from its state via `../data.tf` (a `terraform_remote_state`
data source). Just apply this layer, then apply the clusters layer with its
`attendee_projects` var left unset.

If you'd rather hand off by value (e.g. to edit IDs by hand, or the two layers
don't share a filesystem), print a ready-to-paste block and set the var
explicitly in `../terraform.tfvars`:

```sh
tofu output -raw attendee_projects_tfvars
```

## What gets created

- `google_project` per attendee — `<prefix>-<firstlast>-<random>` (the attendee
  fragment is derived from each email's `first.last` local part → `firstlast`;
  the random suffix keeps the globally-unique project ID from colliding), under
  `parent` (an org or folder), billed to `billing_account`, with the default network disabled.
  GCP caps `project_id` at 30 chars, so the `firstlast` fragment is truncated to
  fit (`30 - len(prefix) - 8`); the **full** `firstlast` is still the resource
  key and appears in the `attendee_emails` output, and the random suffix keeps
  even truncated IDs unique. Use a short `prefix` to leave more room for names.
- `google_project_iam_member` — grants each attendee's email admin-level access
  (`roles/editor` by default, override with `attendee_role`) on **their own**
  project only. Additive, so it doesn't disturb other project IAM. `roles/owner`
  is intentionally not the default: GCP blocks granting owner to users outside
  the org's domain via the API (`ORG_MUST_INVITE_EXTERNAL_OWNERS`).
- `google_project_service` — each API in `var.apis` enabled in each project.

## Tear down

Projects are **protected**: `deletion_policy = "PREVENT"` means `tofu destroy`
(or removing an attendee) will **error** rather than delete a project — a
guardrail against wiping attendee environments by accident.

To intentionally remove a project, either delete it manually in the console /
`gcloud projects delete <id>`, or temporarily switch `deletion_policy` to
`"DELETE"` in `main.tf`, `apply`, then `destroy`.
