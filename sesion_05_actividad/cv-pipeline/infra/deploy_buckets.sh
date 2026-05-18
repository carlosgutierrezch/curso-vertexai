#!/bin/bash
# Crea los 3 buckets del pipeline: input, markdown, json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$ROOT_DIR/.env"

SUFFIX="${USER_SUFFIX:+-$USER_SUFFIX}"

for BUCKET in "$BUCKET_INPUT" "$BUCKET_MARKDOWN" "$BUCKET_JSON"; do
  NAME="${BUCKET}${SUFFIX}"
  if gcloud storage buckets describe "gs://${NAME}" >/dev/null 2>&1; then
    echo "Bucket gs://${NAME} ya existe — skip"
  else
    echo "Creando gs://${NAME} en ${REGION}"
    gcloud storage buckets create "gs://${NAME}" \
      --project="$PROJECT_ID" \
      --location="$REGION" \
      --uniform-bucket-level-access
  fi
done
