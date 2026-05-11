#!/usr/bin/env bash
set -euo pipefail

SECRETS_DIR="$HOME/.secrets/bedrock"

read_secret() {
  local file="$SECRETS_DIR/$1"
  [[ -f "$file" ]] || { echo "Missing secret file: $file"; exit 1; }
  cat "$file"
}

GITHUB_RUNNER_TOKEN=$(read_secret github_runner_token)
GHCR_PAT=$(read_secret ghcr_pat)

ansible-playbook -i inventory/hosts.yaml -K playbooks/cluster.yaml \
  --extra-vars "github_runner_token=${GITHUB_RUNNER_TOKEN} ghcr_pat=${GHCR_PAT}"
