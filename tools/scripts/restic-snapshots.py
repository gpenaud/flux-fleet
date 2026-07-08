#!/usr/bin/env python3
"""
Gère les snapshots restic d'un tenant/stack sur le bucket alter-it-<cluster>-backup-*.

Usage :
    python3 restic-snapshots.py --list
    python3 restic-snapshots.py --list --json
    python3 restic-snapshots.py --download
    python3 restic-snapshots.py --list --cluster infra02

Raccourci tenant+stack : 2 chiffres (position dans le menu).
    python3 restic-snapshots.py --list 21        # tenant 2 (le-portail), stack 1 (alterconso)
    python3 restic-snapshots.py --download 11    # tenant 1 (ferme-du-jointout), stack 1 (dolibarr)
"""

import argparse
import base64
import json
import os
import subprocess
import sys

S3_ENDPOINT = "https://s3.sbg.io.cloud.ovh.net"
DEFAULT_CLUSTER = "infra01"
K8UP_SECRET = "k8up-credentials"
DOWNLOAD_ROOT = "/tmp"

# Inventaire des stacks par tenant (déduit du cluster).
STACKS: dict[str, list[str]] = {
    "ferme-du-jointout": ["dolibarr", "nextcloud", "wordpress-site"],
    "le-portail": ["alterconso", "dolibarr", "grist", "wordpress-epilibres", "wordpress-site"],
    "la-bergeronnette": ["wordpress-site"],
}


def bucket_prefix_for(cluster: str) -> str:
    """Construit le préfixe de bucket pour un cluster donné."""
    return f"alter-it-{cluster}-backup-"


def pick(prompt: str, options: list[str]) -> str:
    """Petit menu numéroté en CLI."""
    print(f"\n{prompt}")
    for i, opt in enumerate(options, 1):
        print(f"  {i}. {opt}")
    while True:
        raw = input("Choix : ").strip()
        if raw.isdigit() and 1 <= int(raw) <= len(options):
            return options[int(raw) - 1]
        print(f"  → entre 1 et {len(options)}")


def pick_tenant_or_full() -> tuple[str, str | None]:
    """Prompt tenant : un seul chiffre = tenant, deux chiffres (ex: 21) = tenant+stack."""
    tenants = list(STACKS.keys())
    print("\nTenant ? (raccourci : 2 chiffres pour cibler tenant+stack, ex: 21)")
    for i, t in enumerate(tenants, 1):
        stacks_preview = " · ".join(f"{j}. {s}" for j, s in enumerate(STACKS[t], 1))
        print(f"  {i}. {t}   [{stacks_preview}]")
    while True:
        raw = input("Choix : ").strip()
        if raw.isdigit() and len(raw) == 1 and 1 <= int(raw) <= len(tenants):
            return tenants[int(raw) - 1], None
        if raw.isdigit() and len(raw) == 2:
            try:
                return resolve_shortcut(raw)
            except ValueError as e:
                print(f"  → {e}")
                continue
        print(f"  → 1..{len(tenants)} pour un tenant, ou 2 chiffres pour tenant+stack")


def get_secret_value(namespace: str, key: str) -> str:
    """Récupère une clé d'un Secret K8s, base64-décodée."""
    cmd = [
        "kubectl", "-n", namespace,
        "get", "secret", K8UP_SECRET,
        "-o", f"jsonpath={{.data.{key}}}",
    ]
    out = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return base64.b64decode(out.stdout).decode().strip()


def build_env(namespace: str, bucket: str) -> dict[str, str]:
    """Prépare les variables d'env pour restic."""
    env = os.environ.copy()
    env["RESTIC_REPOSITORY"] = f"s3:{S3_ENDPOINT}/{bucket}"

    for var in ("RESTIC_PASSWORD", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"):
        if not env.get(var):
            print(f"  ↳ lecture de {var} depuis secret/{K8UP_SECRET} (ns={namespace})")
            env[var] = get_secret_value(namespace, var)
    return env


def resolve_shortcut(code: str) -> tuple[str, str]:
    """Convertit un code à 2 chiffres '21' en (tenant, stack) selon l'ordre de STACKS."""
    if not code.isdigit() or len(code) != 2:
        raise ValueError(f"format attendu : 2 chiffres (ex: 21), reçu : {code!r}")
    tenants = list(STACKS.keys())
    t_idx, s_idx = int(code[0]) - 1, int(code[1]) - 1
    if not 0 <= t_idx < len(tenants):
        raise ValueError(f"tenant {code[0]} hors plage (1..{len(tenants)})")
    tenant = tenants[t_idx]
    stacks = STACKS[tenant]
    if not 0 <= s_idx < len(stacks):
        raise ValueError(f"stack {code[1]} hors plage pour {tenant} (1..{len(stacks)})")
    return tenant, stacks[s_idx]


def select_repo(shortcut: str | None, cluster: str) -> tuple[str, dict[str, str]]:
    """Sélection tenant/stack (raccourci ou menu interactif) + préparation de l'env restic."""
    if shortcut:
        tenant, stack = resolve_shortcut(shortcut)
    else:
        tenant, stack = pick_tenant_or_full()
        if stack is None:
            stack = pick(f"Stack dans {tenant} ?", STACKS[tenant])
    namespace = f"{tenant}-{stack}"
    bucket = f"{bucket_prefix_for(cluster)}{namespace}"
    print("\nCible :")
    print(f"  cluster   : {cluster}")
    print(f"  tenant    : {tenant}")
    print(f"  stack     : {stack}")
    print(f"  namespace : {namespace}")
    print(f"  bucket    : {bucket}")
    return namespace, build_env(namespace, bucket)


def run_list(as_json: bool, shortcut: str | None, cluster: str) -> int:
    _, env = select_repo(shortcut, cluster)
    cmd = ["restic", "snapshots"]
    if as_json:
        cmd.append("--json")
    print(f"\n→ {' '.join(cmd)}\n")
    return subprocess.run(cmd, env=env).returncode


def run_download(shortcut: str | None, cluster: str) -> int:
    namespace, env = select_repo(shortcut, cluster)

    print(f"\n→ restic snapshots --json")
    out = subprocess.run(
        ["restic", "snapshots", "--json"],
        env=env, capture_output=True, text=True, check=True,
    )
    snapshots = json.loads(out.stdout)
    if not snapshots:
        print("\n✗ Aucun snapshot disponible.", file=sys.stderr)
        return 1

    snapshots.sort(key=lambda s: s["time"], reverse=True)
    to_download = [snapshots[0]]
    if len(snapshots) > 1 and snapshots[1].get("paths") != snapshots[0].get("paths"):
        to_download.append(snapshots[1])

    target_dir = os.path.join(DOWNLOAD_ROOT, f"restic-{namespace}")
    os.makedirs(target_dir, exist_ok=True)
    print(f"\n→ Téléchargement dans {target_dir}/")

    for snap in to_download:
        short_id = snap["short_id"]
        sub_target = os.path.join(target_dir, short_id)
        os.makedirs(sub_target, exist_ok=True)
        print(f"\n  • snapshot {short_id} (paths={snap.get('paths')}, time={snap['time']})")
        print(f"    → {sub_target}/")
        rc = subprocess.run(
            ["restic", "restore", snap["id"], "--target", sub_target],
            env=env,
        ).returncode
        if rc != 0:
            print(f"\n✗ restic restore a échoué pour {short_id}", file=sys.stderr)
            return rc

    print(f"\n✓ Téléchargement terminé : {target_dir}/")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Outils restic pour un tenant/stack k8up.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--list", action="store_true", help="Liste les snapshots du repo")
    mode.add_argument(
        "--download",
        action="store_true",
        help=f"Télécharge le dernier backup (et l'avant-dernier si différent) dans {DOWNLOAD_ROOT}/",
    )
    parser.add_argument("--json", action="store_true", help="(--list) Sortie JSON brute de restic")
    parser.add_argument(
        "--cluster",
        default=DEFAULT_CLUSTER,
        metavar="NAME",
        help=f"Cluster ciblé ; préfixe de bucket alter-it-<cluster>-backup- (défaut: {DEFAULT_CLUSTER})",
    )
    parser.add_argument(
        "code",
        nargs="?",
        help="Raccourci tenant+stack à 2 chiffres (ex: 21 = tenant 2, stack 1). Sinon, menu interactif.",
    )
    args = parser.parse_args()

    try:
        if args.list:
            return run_list(args.json, args.code, args.cluster)
        return run_download(args.code, args.cluster)
    except ValueError as e:
        print(f"\n✗ {e}", file=sys.stderr)
        return 2
    except subprocess.CalledProcessError as e:
        err = (e.stderr or "").strip() or str(e)
        print(f"\n✗ Commande en échec : {err}", file=sys.stderr)
        return 1
    except FileNotFoundError as e:
        print(f"\n✗ Binaire introuvable : {e.filename}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())