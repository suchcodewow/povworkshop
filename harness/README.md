# Harness Workshop Organization

Creates a single **Harness Platform (NextGen) organization** for the workshop,
using the [`harness/harness`](https://registry.terraform.io/providers/harness/harness/latest)
provider. This is a standalone layer — it only needs a Harness **account ID**
and a **Platform API key/token**.

## Prerequisites

1. Terraform (>= 1.5) or OpenTofu (>= 1.6).
2. A Harness account ID.
3. A Platform API key (token) with permission to create organizations. Create
   one under **Account Settings → Access Control → Service Accounts / API Keys**
   (or a personal access token). Tokens look like `pat.xxxx...` or `sat.xxxx...`.

## Configure

Pass credentials via environment variables (recommended — keeps the token out
of files and state):

```sh
export HARNESS_ACCOUNT_ID="your_account_id"
export HARNESS_PLATFORM_API_KEY="pat.xxxxx.xxxxx.xxxxx"
```

Then set the org details:

```sh
cp terraform.tfvars.example terraform.tfvars   # edit org_identifier / org_name
```

> `org_identifier` must start with a letter/underscore and use only letters,
> digits, and underscores — no hyphens or spaces.

## Usage

```sh
# Terraform
terraform init && terraform plan && terraform apply

# ...or OpenTofu
tofu init && tofu plan && tofu apply
```

## Outputs

- `org_identifier` — use this as the `org_id` for any org-scoped Harness
  resources you add later (projects, pipelines, connectors).
- `org_id` — the resource ID of the created organization.

## Import an existing org

```sh
terraform import harness_platform_organization.workshop <organization_id>
```
