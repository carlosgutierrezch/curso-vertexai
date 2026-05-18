#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$ROOT_DIR/.env"

SERVICE_NAME="parser${USER_SUFFIX:+-$USER_SUFFIX}"
MARKDOWN_BUCKET_FULL="${BUCKET_MARKDOWN}${USER_SUFFIX:+-$USER_SUFFIX}"

gcloud functions deploy "$SERVICE_NAME" \
  --gen2 \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --runtime=python311 \
  --source="$SCRIPT_DIR" \
  --entry-point=parse \
  --trigger-http \
  --allow-unauthenticated \
  --timeout=120s \
  --set-env-vars="MARKDOWN_BUCKET=${MARKDOWN_BUCKET_FULL}"
