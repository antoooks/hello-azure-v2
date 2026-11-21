#!/usr/bin/env bash
# Mirror the images listed in a mirroring list into an Azure Container Registry with `az acr import`.
# Run with -h for usage.
set -euo pipefail

usage() {
  local me
  me="$(basename "$0")"
  cat <<EOF
Usage: $me [-h|--help] <list.yaml> [target-registry]

Copies every image in <list.yaml> from its sourceRegistry into an Azure Container Registry
using 'az acr import'. The copy happens server-side in Azure (no Docker needed), and images
that already exist in the target are skipped, so the script is safe to re-run.

Arguments:
  <list.yaml>        Mirroring list, e.g. mirroring/test/io.docker.yaml. It must contain
                     'sourceRegistry:' and '- name: <image>:<tag>' entries.
  [target-registry]  Target ACR, as a name (e.g. uqhacrtest) or login server (uqhacrtest.azurecr.io).
                     Defaults to the list's 'targetRegistryName:' or 'targetRegistry:'.

Options:
  -h, --help         Show this help and exit.

Environment:
  SRC_USER, SRC_PASS Credentials for the source registry. Required for private sources
                     such as uniquecr.azurecr.io (app.unique.yaml). Optional for Docker Hub,
                     where they avoid anonymous pull rate limits ('toomanyrequests').

Prerequisites:
  az login, with permission to import into the target registry (e.g. Contributor or Owner).

Examples:
  # Public images into the registry named in each list
  for f in mirroring/test/io.*.yaml; do $me "\$f"; done

  # Public images into an explicit registry
  $me mirroring/test/io.quay.yaml uqhacranto

  # Unique images (private source); read -s keeps the password out of shell history
  read -r -p "uniquecr username: " SRC_USER; read -r -s -p "uniquecr password: " SRC_PASS; echo
  SRC_USER="\$SRC_USER" SRC_PASS="\$SRC_PASS" $me mirroring/test/app.unique.yaml uqhacranto
EOF
}

die() {
  echo "Error: $*" >&2
  echo "Run '$(basename "$0") --help' for usage." >&2
  exit 1
}

# --- arguments ---------------------------------------------------------------
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "") usage >&2; exit 1 ;;
  -*) die "unknown option: $1" ;;
esac

LIST="$1"
[[ -f "$LIST" ]] || die "list file not found: $LIST"
[[ $# -le 2 ]] || die "too many arguments"

SRC="$(awk -F': ' '/^sourceRegistry:/{print $2; exit}' "$LIST" | tr -d '[:space:]')"
[[ -n "$SRC" ]] || die "no 'sourceRegistry:' in $LIST"

# Target: argument, else the list's targetRegistryName / targetRegistry.
TARGET="${2:-}"
if [[ -z "$TARGET" ]]; then
  TARGET="$(awk -F': ' '/^targetRegistry(Name)?:/{print $2; exit}' "$LIST" | tr -d '[:space:]')"
  [[ -n "$TARGET" ]] || die "no target registry given and none found in $LIST"
fi
TARGET="${TARGET%.azurecr.io}" # az acr import --name wants the registry name, not the login server

if [[ -n "${SRC_USER:-}" && -z "${SRC_PASS:-}" ]]; then
  die "SRC_USER is set but SRC_PASS is empty"
fi

echo "Mirroring $LIST: $SRC => $TARGET"

# --- import ------------------------------------------------------------------
awk -F': ' '/^[[:space:]]*- name:/{print $2}' "$LIST" | sed 's/[[:space:]]*#.*//' | while read -r IMG; do
  [[ -n "$IMG" ]] || continue
  SRC_IMG="$IMG"
  # Docker Hub official images live under library/
  if [[ "$SRC" == "docker.io" && "$IMG" != */* ]]; then SRC_IMG="library/$IMG"; fi
  echo "-> $SRC/$SRC_IMG  =>  $TARGET/$IMG"
  args=(--name "$TARGET" --source "$SRC/$SRC_IMG" --image "$IMG")
  if [[ -n "${SRC_USER:-}" ]]; then args+=(--username "$SRC_USER" --password "$SRC_PASS"); fi
  if ! out="$(az acr import "${args[@]}" 2>&1)"; then
    if [[ "$out" == *"already exists"* ]]; then echo "   already there, skipped"; else echo "$out"; exit 1; fi
  fi
done
