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


def run(args: list[str], chdir: Path) -> int:
    """Run BIN with -chdir=<chdir> and the given args; stream output live."""
    cmd = [BIN, f"-chdir={chdir}", *args]
    print(f"\n$ {' '.join(cmd)}\n")
    result = subprocess.run(cmd)
    if result.returncode != 0:
        print(f"\n!! command exited with status {result.returncode}")
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
        return run([action, *extra], d)

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
        if run([action, *extra], d) != 0:
            rc = 1
    return rc


def apply_all() -> None:
    """Apply every layer in order; stop at the first failure."""
    for layer in LAYERS:
        print(f"\n########## APPLY: {layer['key']} ##########")
        if act(layer, "apply") != 0:
            print(f"\n!! stopping — {layer['key']} apply failed.")
            return
    print("\nAll layers applied.")


def destroy_all() -> None:
    """Destroy in reverse order. Skips `projects` (deletion is protected)."""
    for layer in reversed(LAYERS):
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


def show_outputs() -> None:
    print("\nWhich layer's outputs?")
    for i, layer in enumerate(LAYERS, 1):
        print(f"  {i}) {layer['key']}")
    choice = input("layer number (blank to cancel): ").strip()
    if not choice.isdigit() or not (1 <= int(choice) <= len(LAYERS)):
        return
    run(["output"], layer_dir(LAYERS[int(choice) - 1]))


# --- menu -------------------------------------------------------------------

def build_menu() -> list[tuple[str, callable]]:
    items: list[tuple[str, callable]] = []
    for layer in LAYERS:
        # `apply` runs a plan and shows it before prompting, so "plan & apply"
        # is a single step. destroy stays separate.
        for label, action in (("plan & apply", "apply"), ("destroy", "destroy")):
            items.append((f"{layer['name']:<44s} {label}",
                          lambda l=layer, a=action: act(l, a)))
    items.append(("ALL: apply  (harness -> projects -> clusters -> addons -> k8s)", lambda: apply_all()))
    items.append(("ALL: destroy (k8s -> addons -> clusters -> harness)", lambda: destroy_all()))
    items.append(("Clean up orphaned clusters (delete GKE clusters not in state)", lambda: cleanup_orphans()))
    items.append(("Show outputs for a layer", lambda: show_outputs()))
    items.append(("Manage secrets (push secrets.local.env -> Secret Manager)", lambda: manage_secrets()))
    items.append(("Reload secrets from Secret Manager", lambda: load_secrets()))
    return items


def main() -> None:
    load_secrets()
    items = build_menu()
    while True:
        print(f"\n=== Workshop Terraform ({BIN}) — auto-approve ===")
        for i, (label, _) in enumerate(items, 1):
            print(f"  {i:2d}) {label}")
        print("   q) Quit")
        choice = input("\nSelect: ").strip().lower()
        if choice in ("q", "quit", "exit"):
            return
        if not choice.isdigit() or not (1 <= int(choice) <= len(items)):
            print("!! invalid choice")
            continue
        try:
            items[int(choice) - 1][1]()
        except KeyboardInterrupt:
            print("\n(interrupted — back to menu)")


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print("\nbye")
