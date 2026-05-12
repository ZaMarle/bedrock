#!/usr/bin/env bash
set -euo pipefail

SECRETS_DIR="$HOME/.secrets/bedrock"

read_secret() {
  local file="$SECRETS_DIR/$1"
  [[ -f "$file" ]] || { echo "Missing secret file: $file"; exit 1; }
  cat "$file"
}

GITHUB_PAT_RUNNER_REG_GEN=$(read_secret github_pat_runner_reg_gen)
GHCR_PAT=$(read_secret ghcr_pat)

echo "Logging in to ghcr.io..."
echo "${GHCR_PAT}" | docker login ghcr.io -u zamarle --password-stdin

echo "Building runner image..."
docker build -t ghcr.io/zamarle/github-runner:latest roles/github-runner/files/

echo "Pushing runner image..."
docker push ghcr.io/zamarle/github-runner:latest

GITHUB_REPOS=(vevous escrow)
RUNNER_TOKENS="{}"

for repo in "${GITHUB_REPOS[@]}"; do
  echo "Fetching runner registration token for ${repo}..."
  token=$(curl -s -X POST \
    -H "Authorization: Bearer ${GITHUB_PAT_RUNNER_REG_GEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/zamarle/${repo}/actions/runners/registration-token" \
    | jq -r .token)
  RUNNER_TOKENS=$(echo "$RUNNER_TOKENS" | jq --arg r "$repo" --arg t "$token" '. + {($r): $t}')
done

TMPFILE=$(mktemp)
trap "rm -f ${TMPFILE}" EXIT
jq -n --argjson tokens "$RUNNER_TOKENS" --arg ghcr_pat "$GHCR_PAT" \
  '{runner_tokens: $tokens, ghcr_pat: $ghcr_pat}' > "$TMPFILE"

ansible-playbook -i inventory/hosts.yaml -K -k playbooks/cluster.yaml \
  --extra-vars "@${TMPFILE}"
