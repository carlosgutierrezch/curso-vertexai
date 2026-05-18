#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$ROOT_DIR/.env"

SERVICE_NAME="extractor${USER_SUFFIX:+-$USER_SUFFIX}"
JSON_BUCKET_FULL="${BUCKET_JSON}${USER_SUFFIX:+-$USER_SUFFIX}"

gcloud functions deploy "$SERVICE_NAME" \
  --gen2 \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --runtime=python311 \
  --source="$SCRIPT_DIR" \
  --entry-point=extract \
  --trigger-http \
  --allow-unauthenticated \
  --timeout=120s \
  --set-env-vars="JSON_BUCKET=${JSON_BUCKET_FULL},PROJECT_ID=${PROJECT_ID},REGION=${REGION}"
