#!/usr/bin/env python3
"""Interactive menu for the workshop Terraform/OpenTofu layers.

Runs the layers in their documented order:

    harness -> projects -> clusters -> addons -> k8s-addons (per attendee)

Pick a step from the menu; it runs the tofu/terraform command, streams the
output live, and drops you back at the menu. Requires `tofu` (preferred) or
`terraform` on PATH; override with the TF_BIN environment variable.

Secrets (Harness token, GCP billing/parent, attendee emails) live in GCP
Secret Manager in a central operator project; on startup they're loaded into
the environment (as HARNESS_* / TF_VAR_*) so every layer runs without typing
anything in. See workshop.config.json and the "Manage secrets" menu item.
"""

from __future__ import annotations

import datetime
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent

# Layers in apply order. `dir` is relative to this repo root; each layer lives
# in its own subfolder. `per_attendee` layers use one workspace per attendee.
LAYERS = [
    {"key": "harness", "dir": "harness", "name": "Harness   (workshop organization)",
     "requires": ["HARNESS_ACCOUNT_ID", "HARNESS_PLATFORM_API_KEY"]},
    {"key": "projects", "dir": "projects", "name": "Projects  (attendee GCP projects)"},
    {"key": "clusters", "dir": "kubernetes", "name": "Clusters  (GKE + network + registry)"},
    {"key": "addons", "dir": "addons", "name": "Add-ons   (firewall, Binary Authorization)"},
    {"key": "k8s", "dir": "k8s-addons", "name": "K8s add-ons (in-cluster, per attendee)", "per_attendee": True},
    {"key": "trivy", "dir": "trivy", "name": "Trivy     (standalone shared scanner project)", "standalone": True},
    {"key": "zap", "dir": "zap", "name": "OWASP ZAP (standalone DAST scanner project)", "standalone": True},
]

# Directory of the clusters layer (used directly when reading its state/outputs).
CLUSTERS_DIR = (ROOT / "kubernetes").resolve()

# --- configuration & secrets ------------------------------------------------
#
# workshop.config.json (committed, NO secrets) holds the central operator
# project that stores the secrets, plus a mapping of env-var name -> Secret
# Manager secret name. Secret VALUES never live in the repo — only in Secret
# Manager. WORKSHOP_OPERATOR_PROJECT overrides the operator project.

CONFIG_FILE = ROOT / "workshop.config.json"
LOCAL_SECRETS_FILE = ROOT / "secrets.local.env"  # one-time bootstrap input (gitignored)


def load_config() -> dict:
    cfg = {"operator_project": None, "secrets": {}}
    if CONFIG_FILE.exists():
        try:
            cfg.update(json.loads(CONFIG_FILE.read_text()))
        except (json.JSONDecodeError, OSError) as e:
            print(f"!! could not read {CONFIG_FILE.name}: {e}")
    env_proj = os.environ.get("WORKSHOP_OPERATOR_PROJECT")
    if env_proj:
        cfg["operator_project"] = env_proj
    return cfg


CONFIG = load_config()
SECRETS: dict[str, str] = CONFIG.get("secrets", {})       # env var -> secret name
OPERATOR_PROJECT: str | None = CONFIG.get("operator_project")

# Optional operator service account to impersonate. WORKSHOP_IMPERSONATE_SA
# overrides workshop.config.json's "operator_service_account". A placeholder
# ("REPLACE...") or empty value means "don't impersonate".
IMPERSONATE_SA: str | None = (
    os.environ.get("WORKSHOP_IMPERSONATE_SA")
    or CONFIG.get("operator_service_account")
    or None
)
if IMPERSONATE_SA and "REPLACE" in IMPERSONATE_SA:
    IMPERSONATE_SA = None


def configure_impersonation() -> None:
    """Impersonate the operator service account (if configured) for BOTH
    Terraform's google provider and gcloud, so runs use the SA's identity rather
    than the user's. This avoids user reauth (invalid_rapt) and matches the
    central-operator model.

    Sets the env vars both tools already understand — no provider edits needed:
      GOOGLE_IMPERSONATE_SERVICE_ACCOUNT      -> terraform-provider-google
      CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT -> gcloud

    Requires the caller's ADC identity to have roles/iam.serviceAccountTokenCreator
    on the target SA. If nothing is configured, runs use the user's own ADC.
    """
    if not IMPERSONATE_SA:
        return
    print(f"(impersonating service account: {IMPERSONATE_SA})")
    # Preflight BEFORE setting the impersonation env vars, so the ADC check below
    # tests the raw source credential rather than an impersonated one.
    _preflight_impersonation()
    os.environ.setdefault("GOOGLE_IMPERSONATE_SERVICE_ACCOUNT", IMPERSONATE_SA)
    os.environ.setdefault("CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT", IMPERSONATE_SA)


def _preflight_impersonation() -> None:
    """Confirm impersonation will actually work, with a clear hint if not.

    Impersonation offloads GCP calls to the SA, but the *source* credential must
    be valid enough to mint the SA token first. Terraform's google provider
    impersonates from ADC (`application-default`), which is a DIFFERENT
    credential from the gcloud CLI login — so a fresh gcloud login isn't enough
    if ADC is reauth-expired (the usual invalid_rapt cause). Check both:
      (a) ADC itself is usable  (what Terraform impersonates FROM), and
      (b) the SA token can be minted (confirms the token-creator grant).
    Tokens are discarded, never printed.
    """
    if not shutil.which("gcloud"):
        return

    # (a) ADC health — the credential Terraform uses. Test it raw.
    code, _t, err = gcloud_capture(["auth", "application-default", "print-access-token"])
    err = (err or "").strip()
    if code != 0:
        tail = err.splitlines()[-1] if err else f"exit {code}"
        print(f"!! ADC (used by Terraform) is not usable: {tail}")
        if "invalid_rapt" in err or "reauth" in err.lower():
            print("   Reauthenticate, then retry:  gcloud auth application-default login")
        else:
            print("   Set it up:  gcloud auth application-default login")
        print("   (google-provider layers will fail until this is fixed.)")
        return

    # (b) Can we mint a token for the SA? Confirms the token-creator grant.
    code, _t2, err2 = gcloud_capture(
        ["auth", "print-access-token", "--impersonate-service-account", IMPERSONATE_SA])
    if code == 0:
        print("(impersonation preflight OK — ADC valid, SA token minted)")
        return
    err2 = (err2 or "").strip()
    tail2 = err2.splitlines()[-1] if err2 else f"exit {code}"
    print(f"!! cannot mint a token for {IMPERSONATE_SA}")
    if any(s in err2.lower() for s in ("permission", "denied", "forbidden", "token creator")):
        print("   Your account likely lacks roles/iam.serviceAccountTokenCreator on the SA.")
    if "invalid_rapt" in err2 or "reauth" in err2.lower():
        print("   Or reauthenticate:  gcloud auth login")
    print(f"   {tail2}")
    print("   (google-provider layers will fail until this is fixed.)")


def tf_bin() -> str:
    """Resolve the Terraform binary: $TF_BIN, then tofu, then terraform."""
    override = os.environ.get("TF_BIN")
    if override:
        return override
    for candidate in ("tofu", "terraform"):
        if shutil.which(candidate):
            return candidate
    sys.exit("error: neither 'tofu' nor 'terraform' found on PATH (set TF_BIN).")


BIN = tf_bin()

# apply/destroy always run non-interactively — no per-command confirmation.
APPROVE = ["-auto-approve"]


def layer_dir(layer: dict) -> Path:
    return (ROOT / layer["dir"]).resolve()


def run(args: list[str], chdir: Path, quiet: bool = False) -> int:
    """Run BIN with -chdir=<chdir> and the given args.

    Normally streams output live. In quiet mode (used for plan/apply/destroy),
    capture the output and surface only what matters: the Terraform Error block
    on failure, or a one-line summary on success. Set WORKSHOP_VERBOSE=1 to
    force full streaming everywhere (for debugging).
    """
    quiet = quiet and not os.environ.get("WORKSHOP_VERBOSE")
    cmd = [BIN, f"-chdir={chdir}", *args]
    if quiet:
        cmd.append("-no-color")  # keep captured text clean
    print(f"\n$ {' '.join(cmd)}\n")

    if not quiet:
        result = subprocess.run(cmd)
        if result.returncode != 0:
            print(f"\n!! command exited with status {result.returncode}")
        return result.returncode

    result = subprocess.run(cmd, capture_output=True, text=True)
    out = result.stdout or ""
    err = result.stderr or ""
    if result.returncode != 0:
        # Terraform writes Error:/Warning: blocks to stderr; fall back to the
        # tail of stdout if stderr is empty.
        print((err.strip() or "\n".join(out.strip().splitlines()[-20:])))
        print(f"\n!! command exited with status {result.returncode}")
    else:
        summary = [ln for ln in out.splitlines()
                   if ln.startswith(("Apply complete!", "Destroy complete!",
                                     "Plan:", "No changes.", "Changes to Outputs"))]
        print("\n".join(summary) if summary else "(done)")
        if err.strip():  # surface warnings even on success
            print(err.strip())
    return result.returncode


def capture(args: list[str], chdir: Path) -> tuple[int, str]:
    """Run BIN quietly and capture stdout (used to read outputs)."""
    cmd = [BIN, f"-chdir={chdir}", *args]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout


def ensure_init(layer: dict) -> bool:
    """Run `init` once if the layer hasn't been initialized yet."""
    d = layer_dir(layer)
    if (d / ".terraform").exists():
        return True
    print(f"(initializing {layer['key']} — first run)")
    return run(["init", "-input=false"], d) == 0


def get_attendees() -> list[str]:
    """Read the attendee list from the clusters layer's `attendees` output."""
    code, out = capture(["output", "-json", "attendees"], CLUSTERS_DIR)
    if code != 0 or not out.strip():
        return []
    try:
        return list(json.loads(out))
    except json.JSONDecodeError:
        return []


def get_attendee_projects() -> dict[str, str]:
    """Read the attendee -> project map.

    Prefer the clusters layer's output, but fall back to the projects/ factory
    layer — the clusters output disappears after a destroy, while the factory
    output survives (those projects are protected), and orphaned clusters may
    still exist in GCP exactly in that situation.
    """
    for chdir in (CLUSTERS_DIR, (ROOT / "projects").resolve()):
        code, out = capture(["output", "-json", "attendee_projects"], chdir)
        if code == 0 and out.strip():
            try:
                projects = dict(json.loads(out))
            except json.JSONDecodeError:
                continue
            if projects:
                return projects
    return {}


def gcloud_capture(args: list[str]) -> tuple[int, str, str]:
    result = subprocess.run(["gcloud", *args], capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def gcloud_run(args: list[str]) -> int:
    cmd = ["gcloud", *args]
    print(f"\n$ {' '.join(cmd)}\n")
    return subprocess.run(cmd).returncode


# --- secrets (GCP Secret Manager) -------------------------------------------

def access_secret(name: str) -> str | None:
    """Read the latest version of a secret; None if missing/unreadable."""
    if not OPERATOR_PROJECT:
        return None
    code, out, _ = gcloud_capture(
        ["secrets", "versions", "access", "latest",
         "--secret", name, "--project", OPERATOR_PROJECT])
    # Strip a single trailing newline (e.g. if a value was stored via `echo`);
    # tokens/ids/JSON never rely on one.
    return out[:-1] if code == 0 and out.endswith("\n") else (out if code == 0 else None)


def load_secrets() -> None:
    """Populate os.environ from Secret Manager so terraform/harness inherit it.

    Values already set in the environment WIN (a hand-exported value overrides
    the stored one). Missing secrets are skipped — a layer that needs one will
    fail loudly on its own.
    """
    if not SECRETS:
        return
    if not OPERATOR_PROJECT:
        print("!! no operator_project (workshop.config.json / "
              "WORKSHOP_OPERATOR_PROJECT) — skipping secret load.")
        return
    if not shutil.which("gcloud"):
        print("!! gcloud not found — cannot load secrets.")
        return
    loaded, missing = [], []
    for env_var, secret_name in SECRETS.items():
        if os.environ.get(env_var):
            continue  # already set by hand — don't clobber
        val = access_secret(secret_name)
        if val is None:
            missing.append(f"{env_var}<-{secret_name}")
            continue
        os.environ[env_var] = val
        loaded.append(env_var)
    if loaded:
        print(f"(loaded {len(loaded)} secret(s): {', '.join(loaded)})")
    if missing:
        print(f"(unset: {', '.join(missing)} — populate via 'Manage secrets')")


def set_derived_vars() -> None:
    """Derive the Harness org name/identifier from the current month.

    name       = "<Month>_INT"  (e.g. July_INT)
    identifier = "<month>_int"  (lowercase, e.g. july_int)

    Passed to Terraform as TF_VAR_org_name / TF_VAR_org_identifier. Using a
    concrete string here (rather than timestamp() inside Terraform) keeps the
    value stable within a month — so no spurious diffs — while still rolling to
    a new org each month. An explicit export wins (setdefault).
    """
    month = datetime.date.today().strftime("%B")  # full month name, e.g. "July"
    os.environ.setdefault("TF_VAR_org_name", f"{month}_INT")
    os.environ.setdefault("TF_VAR_org_identifier", f"{month.lower()}_int")


def manage_secrets() -> None:
    """One-time setup: push local secret values up to Secret Manager.

    Reads KEY=VALUE lines from secrets.local.env (gitignored), where KEY is one
    of the env-var names in SECRETS. Creates each secret if needed, then adds a
    new version from stdin (so the value never appears in argv). Delete
    secrets.local.env afterward — the values then live only in Secret Manager.
    """
    if not OPERATOR_PROJECT:
        print("!! set operator_project in workshop.config.json first.")
        return
    if not shutil.which("gcloud"):
        print("!! gcloud not found.")
        return
    if not LOCAL_SECRETS_FILE.exists():
        print(f"!! create {LOCAL_SECRETS_FILE.name} with KEY=VALUE lines, then "
              f"re-run. Keys: {', '.join(SECRETS) or '(none configured)'}")
        return

    gcloud_run(["services", "enable", "secretmanager.googleapis.com",
                "--project", OPERATOR_PROJECT])

    values: dict[str, str] = {}
    for line in LOCAL_SECRETS_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        values[k.strip()] = v.strip()

    for env_var, secret_name in SECRETS.items():
        if env_var not in values:
            print(f"  (skip {secret_name}: no {env_var} in {LOCAL_SECRETS_FILE.name})")
            continue
        code, _, _ = gcloud_capture(
            ["secrets", "describe", secret_name, "--project", OPERATOR_PROJECT])
        if code != 0:
            gcloud_run(["secrets", "create", secret_name,
                        "--replication-policy", "automatic",
                        "--project", OPERATOR_PROJECT])
        proc = subprocess.run(
            ["gcloud", "secrets", "versions", "add", secret_name,
             "--data-file=-", "--project", OPERATOR_PROJECT],
            input=values[env_var], text=True)
        print(f"  {secret_name}: {'ok' if proc.returncode == 0 else f'FAILED ({proc.returncode})'}")

    print(f"\nDone. Now DELETE {LOCAL_SECRETS_FILE.name} — the values live in "
          "Secret Manager. Reload with 'Reload secrets' or restart.")


def select_workspace(d: Path, name: str) -> int:
    """Select (creating if needed) a workspace, for tofu or terraform."""
    if Path(BIN).name == "terraform":
        if run(["workspace", "select", name], d) != 0:
            return run(["workspace", "new", name], d)
        return 0
    return run(["workspace", "select", "-or-create", name], d)


# --- per-layer actions ------------------------------------------------------

def missing_required_env(layer: dict) -> list[str]:
    """Env-var credentials a layer needs that are neither set nor plausibly
    supplied by a local terraform.tfvars in that layer."""
    required = layer.get("requires", [])
    if not required:
        return []
    # A committed/local terraform.tfvars may provide the values instead of env.
    if (layer_dir(layer) / "terraform.tfvars").exists():
        return []
    return [v for v in required if not os.environ.get(v)]


def act(layer: dict, action: str) -> int:
    """Run plan/apply/destroy for a layer (looping attendees if per-attendee)."""
    missing = missing_required_env(layer)
    if missing:
        print(f"!! {layer['key']}: required credential(s) not set: {', '.join(missing)}")
        print("   These load from Secret Manager on startup. Fix by either:")
        print("     - running via `python3 workshop.py` (loads secrets automatically), or")
        print("     - main menu -> 'Manage secrets' to populate them, then 'Reload secrets', or")
        print("     - exporting them by hand before running.")
        secret_hint = [SECRETS.get(v, "?") for v in missing]
        print(f"   (Secret Manager names: {', '.join(secret_hint)} in {OPERATOR_PROJECT})")
        return 1
    if not ensure_init(layer):
        return 1
    d = layer_dir(layer)
    extra = APPROVE if action in ("apply", "destroy") else []

    if not layer.get("per_attendee"):
        return run([action, *extra], d, quiet=True)

    attendees = get_attendees()
    if not attendees:
        print("!! no attendees found — apply the clusters layer first.")
        return 1
    print(f"(looping {action} over: {', '.join(attendees)})")
    rc = 0
    for a in attendees:
        print(f"\n===== {a} =====")
        if select_workspace(d, a) != 0:
            rc = 1
            continue
        if run([action, *extra], d, quiet=True) != 0:
            rc = 1
    return rc


def apply_all() -> None:
    """Apply every layer in order; stop at the first failure.

    `standalone` layers (e.g. trivy) are skipped — they have independent
    lifecycles and are applied on their own from the menu.
    """
    for layer in LAYERS:
        if layer.get("standalone"):
            continue
        print(f"\n########## APPLY: {layer['key']} ##########")
        if act(layer, "apply") != 0:
            print(f"\n!! stopping — {layer['key']} apply failed.")
            return
    print("\nAll layers applied.")


def destroy_all() -> None:
    """Destroy in reverse order. Skips `projects` (protected) and `standalone`
    layers (independent lifecycle — destroy them on their own)."""
    for layer in reversed(LAYERS):
        if layer.get("standalone"):
            continue
        if layer["key"] == "projects":
            print("\n(skipping projects destroy — projects are protected; "
                  "remove them manually or set deletion_policy = DELETE.)")
            continue
        print(f"\n########## DESTROY: {layer['key']} ##########")
        act(layer, "destroy")


def cleanup_orphans() -> None:
    """Delete GKE clusters that exist in GCP but aren't tracked in state.

    Interrupted applies can leave a cluster running in GCP without recording it
    in state. Terraform then doesn't know the subnet is still in use by that
    cluster's nodes, so `destroy` fails with resourceInUseByAnotherResource.
    Deleting the orphan frees the subnet so the rest can be torn down.
    """
    if not shutil.which("gcloud"):
        print("!! gcloud not found on PATH — needed to find/delete clusters.")
        return
    projects = get_attendee_projects()
    if not projects:
        print("!! no attendee_projects output — apply the projects/clusters "
              "layers first, or nothing to check.")
        return

    tracked = set(capture(["state", "list"], CLUSTERS_DIR)[1].splitlines())

    orphans: list[tuple[str, str, str]] = []  # (project, cluster_name, location)
    for attendee, project in projects.items():
        # If Terraform already tracks this attendee's cluster, `destroy` owns it.
        if f'google_container_cluster.primary["{attendee}"]' in tracked:
            continue
        code, out, err = gcloud_capture(
            ["container", "clusters", "list", "--project", project,
             "--format=value(name,location)"])
        if code != 0:
            tail = err.strip().splitlines()[-1] if err.strip() else f"exit {code}"
            print(f"!! could not list clusters in {project}: {tail}")
            continue
        for line in filter(None, (ln.strip() for ln in out.splitlines())):
            name, location = line.split()[:2]
            orphans.append((project, name, location))

    if not orphans:
        print("No orphaned clusters found — state and GCP are in sync.")
        return

    print("\nDeleting orphaned clusters (exist in GCP, not in Terraform state):")
    for project, name, location in orphans:
        print(f"  - {name}  ({location})  in {project}")

    for project, name, location in orphans:
        print(f"\n===== deleting {name} =====")
        gcloud_run(["container", "clusters", "delete", name,
                    "--project", project, "--location", location, "--quiet"])
    print("\nDone. Now run a destroy (option for the clusters layer, or ALL: destroy).")


def show_identity() -> None:
    """Show which identity a run will use — your gcloud account and, if set, the
    operator service account being impersonated for Terraform + gcloud."""
    if not shutil.which("gcloud"):
        print("!! gcloud not found on PATH.")
        return
    code, out, _ = gcloud_capture(
        ["auth", "list", "--filter=status:ACTIVE", "--format=value(account)"])
    active = out.strip() if code == 0 else ""
    print("\n=== Identity for this run ===")
    print(f"  gcloud active account : {active or '(none — run: gcloud auth login)'}")
    if IMPERSONATE_SA:
        print(f"  impersonating SA      : {IMPERSONATE_SA}")
        print("    -> Terraform (google provider) and gcloud act AS this SA.")
        print("       Your active account needs roles/iam.serviceAccountTokenCreator on it.")
    else:
        print("  impersonating SA      : (none — using your own ADC)")
    print(f"  operator project      : {OPERATOR_PROJECT or '(unset)'}")


def show_outputs() -> None:
    print("\nWhich layer's outputs?")
    for i, layer in enumerate(LAYERS, 1):
        print(f"  {i}) {layer['key']}")
    choice = input("layer number (blank to cancel): ").strip()
    if not choice.isdigit() or not (1 <= int(choice) <= len(LAYERS)):
        return
    run(["output"], layer_dir(LAYERS[int(choice) - 1]))


# --- menu -------------------------------------------------------------------

def build_menu() -> list[tuple[str, callable | None]]:
    """Menu entries as (label, action). A None action marks a section header
    (printed but not selectable). Build options come first, then teardown, then
    utilities — so there's no interleaving of apply/destroy while building."""
    items: list[tuple[str, callable | None]] = []

    # --- Build (plan & apply) ---
    items.append(("--- Build (plan & apply) ---", None))
    for layer in LAYERS:
        items.append((f"{layer['name']:<44s} plan & apply",
                      lambda l=layer: act(l, "apply")))
    items.append(("ALL: apply  (harness -> projects -> clusters -> addons -> k8s)", lambda: apply_all()))

    # --- Tear down (destroy) ---
    items.append(("--- Tear down (destroy) ---", None))
    for layer in LAYERS:
        items.append((f"{layer['name']:<44s} destroy",
                      lambda l=layer: act(l, "destroy")))
    items.append(("ALL: destroy (k8s -> addons -> clusters -> harness)", lambda: destroy_all()))

    # --- Utilities ---
    items.append(("--- Utilities ---", None))
    items.append(("Clean up orphaned clusters (delete GKE clusters not in state)", lambda: cleanup_orphans()))
    items.append(("Show outputs for a layer", lambda: show_outputs()))
    items.append(("Manage secrets (push secrets.local.env -> Secret Manager)", lambda: manage_secrets()))
    items.append(("Reload secrets from Secret Manager", lambda: load_secrets()))
    items.append(("Show current identity (gcloud account / impersonation)", lambda: show_identity()))
    return items


def main() -> None:
    configure_impersonation()
    load_secrets()
    set_derived_vars()
    items = build_menu()
    while True:
        print(f"\n=== Workshop Terraform ({BIN}) — auto-approve ===")
        # Number only selectable items; headers (action is None) print plainly.
        actions: dict[int, callable] = {}
        n = 0
        for label, action in items:
            if action is None:
                print(f"\n  {label}")
            else:
                n += 1
                actions[n] = action
                print(f"  {n:2d}) {label}")
        print("\n   q) Quit")
        choice = input("\nSelect: ").strip().lower()
        if choice in ("q", "quit", "exit"):
            return
        if not choice.isdigit() or int(choice) not in actions:
            print("!! invalid choice")
            continue
        try:
            actions[int(choice)]()
        except KeyboardInterrupt:
            print("\n(interrupted — back to menu)")


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print("\nbye")
