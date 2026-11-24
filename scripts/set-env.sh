#!/usr/bin/env bash
# Rewrites the environment-specific Azure resource names in 03_applications to match one env value.
#
# Argo CD reads the values files straight from Git without templating, so names such as hakv2<env> or
# uqharedis-<env>-port must be written out in the files. This script keeps them in line with the `env` that
# Terraform uses (02_infrastructure/environments/test/00-parameters-day-*.auto.tfvars).
#
# Usage:
#   ./scripts/set-env.sh              # env from the day-2 tfvars; "test" if it is missing or null
#   ./scripts/set-env.sh <env>        # explicit env, e.g. ./scripts/set-env.sh anto
#   ./scripts/set-env.sh --check [env]  # change nothing; exit 1 if any file does not match (for CI/pre-commit)
#
# Rewritten patterns (prefixes mirror the Terraform defaults in 02_infrastructure/day-2/01-variables.tf):
#   hakv1<env>, hakv2<env>                     Key Vaults           (main_kv_name / sensitive_kv_name)
#   uqhacr<env>.azurecr.io                     Container registry   (container_registry_name)
#   aks-id-<env>                               Workload identity    (aks_user_assigned_identity_name)
#   azurekeyvaultsecretsprovider-aks-<env>     CSI identity (comments)
#   uqhastorage<env>                           Ingestion storage    (ingestion_storage_sa_name)
#   uqharedis-<env>-host|port|password         Redis Key Vault secrets (redis_name)
# Not rewritten: the ACR pull secrets "uqhacrtest-azurecr-io-*", whose names Terraform hard-codes
# (day-2/35-acr-argocd-helm-pull.tf). IDs (client IDs, tenant ID) are not names and must be updated separately.

set -euo pipefail

DEFAULT_ENV="test"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TFVARS_DIR="${REPO_ROOT}/02_infrastructure/environments/test"
TARGET_DIRS=("${REPO_ROOT}/03_applications/test" "${REPO_ROOT}/03_applications/defaults")

check_only=false
if [[ "${1:-}" == "--check" ]]; then
  check_only=true
  shift
fi

# Reads `env = "..."` from a tfvars file. Prints nothing when the line is missing or set to null.
read_tfvars_env() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  sed -nE 's/^[[:space:]]*env[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$file" | head -n1
}

if [[ $# -gt 0 && -n "$1" ]]; then
  env_value="$1"
  source_desc="command line"
else
  env_value="$(read_tfvars_env "${TFVARS_DIR}/00-parameters-day-2.auto.tfvars")"
  source_desc="02_infrastructure/environments/test/00-parameters-day-2.auto.tfvars"
fi
if [[ -z "$env_value" || "$env_value" == "null" ]]; then
  env_value="$DEFAULT_ENV"
  source_desc="default (env missing or null)"
fi

# Storage account and ACR names only allow lowercase letters and digits; "uqhastorage" + env must fit in 24 chars.
if [[ ! "$env_value" =~ ^[a-z0-9]{1,13}$ ]]; then
  echo "error: env must be 1-13 lowercase letters or digits, got '${env_value}'" >&2
  exit 2
fi

# Warn when the Terraform days disagree; they all build resource names from env.
for day in 1 2 3; do
  day_env="$(read_tfvars_env "${TFVARS_DIR}/00-parameters-day-${day}.auto.tfvars")"
  day_env="${day_env:-$DEFAULT_ENV}"
  [[ "$day_env" == "null" ]] && day_env="$DEFAULT_ENV"
  if [[ "$day_env" != "$env_value" ]]; then
    echo "warning: 00-parameters-day-${day}.auto.tfvars has env = \"${day_env}\", not \"${env_value}\"" >&2
  fi
done

echo "env: ${env_value} (from ${source_desc})"

rewrite() {
  ENV_VALUE="$env_value" perl -pe '
    my $e = $ENV{ENV_VALUE};
    s/\bhakv([12])[a-z0-9]+\b/hakv$1$e/g;
    s/\buqhacr[a-z0-9]+(?=\.azurecr\.io\b)/uqhacr$e/g;
    s/\baks-id-[a-z0-9]+\b/aks-id-$e/g;
    s/\bazurekeyvaultsecretsprovider-aks-[a-z0-9]+\b/azurekeyvaultsecretsprovider-aks-$e/g;
    s/\buqhastorage[a-z0-9]+\b/uqhastorage$e/g;
    s/\buqharedis-[a-z0-9]+-(host|port|password)\b/uqharedis-$e-$1/g;
  ' "$1"
}

changed=0
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

while IFS= read -r -d '' file; do
  rewrite "$file" >"$tmp"
  if ! cmp -s "$file" "$tmp"; then
    changed=$((changed + 1))
    rel="${file#"${REPO_ROOT}/"}"
    if $check_only; then
      echo "out of date: ${rel}"
    else
      cat "$tmp" >"$file" # keep the original file's permissions
      echo "updated: ${rel}"
    fi
  fi
done < <(find "${TARGET_DIRS[@]}" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.gotmpl' \) -print0 2>/dev/null)

if $check_only; then
  if [[ $changed -gt 0 ]]; then
    echo "${changed} file(s) do not match env '${env_value}'. Run ./scripts/set-env.sh to fix." >&2
    exit 1
  fi
  echo "all files match env '${env_value}'"
else
  echo "${changed} file(s) updated for env '${env_value}'"
fi
