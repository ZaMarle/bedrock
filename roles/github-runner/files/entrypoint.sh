#!/bin/bash
set -e

/home/runner/config.sh \
  --url "${GITHUB_URL}" \
  --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME:-bedrock-runner}" \
  --work "${RUNNER_WORKDIR:-/home/runner/_work}" \
  --unattended \
  --replace

exec /home/runner/run.sh
