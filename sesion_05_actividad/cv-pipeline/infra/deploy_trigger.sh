#!/bin/bash
# Crea la SA del trigger Eventarc, le asigna roles y registra el trigger
# que conecta GCS (BUCKET_INPUT) con el workflow cv-processing.
# Sigue el codelab: https://codelabs.developers.google.com/codelabs/cloud-event-driven-orchestration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$ROOT_DIR/.env"

SUFFIX="${USER_SUFFIX:+-$USER_SUFFIX}"
SERVICE_ACCOUNT="cv-trigger-sa${SUFFIX}"
SA_EMAIL="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
TRIGGER_NAME="trigger-cv-processing${SUFFIX}"
WORKFLOW_NAME="cv-processing${SUFFIX}"
BUCKET_INPUT_FULL="${BUCKET_INPUT}${SUFFIX}"

# 1. (APIs ya habilitadas por infra/init.sh)

# 2. Crear service account (idempotente)
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Service account $SA_EMAIL ya existe — skip"
else
  echo "Creando service account $SERVICE_ACCOUNT..."
  gcloud iam service-accounts create "$SERVICE_ACCOUNT" \
    --project="$PROJECT_ID" \
    --display-name="Eventarc trigger CV processing"
fi

# 3. Bindings IAM en el proyecto: workflows.invoker + eventarc.eventReceiver para la SA del trigger
echo "Asignando roles a $SA_EMAIL..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --role="roles/workflows.invoker" \
  --member="serviceAccount:${SA_EMAIL}" \
  --condition=None >/dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --role="roles/eventarc.eventReceiver" \
  --member="serviceAccount:${SA_EMAIL}" \
  --condition=None >/dev/null

# 4. Grant pubsub.publisher al SA del Cloud Storage (requerido para eventos GCS via Eventarc)
# Inicializa el service agent si aún no existe en el proyecto (idempotente)
gcloud storage service-agent --project="$PROJECT_ID" >/dev/null 2>&1 || true
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
STORAGE_SERVICE_ACCOUNT="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"
echo "Concediendo pubsub.publisher a ${STORAGE_SERVICE_ACCOUNT}..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --role="roles/pubsub.publisher" \
  --member="serviceAccount:${STORAGE_SERVICE_ACCOUNT}" \
  --condition=None >/dev/null

# 5. Crear el trigger Eventarc (idempotente: borrar si existe y recrear)
if gcloud eventarc triggers describe "$TRIGGER_NAME" \
    --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Trigger $TRIGGER_NAME ya existe — borrando para recrear"
  gcloud eventarc triggers delete "$TRIGGER_NAME" \
    --location="$REGION" --project="$PROJECT_ID" --quiet
fi

echo "Creando trigger $TRIGGER_NAME..."
gcloud eventarc triggers create "$TRIGGER_NAME" \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --destination-workflow="$WORKFLOW_NAME" \
  --destination-workflow-location="$REGION" \
  --event-filters="type=google.cloud.storage.object.v1.finalized" \
  --event-filters="bucket=$BUCKET_INPUT_FULL" \
  --service-account="$SA_EMAIL"

echo "Trigger creado: $TRIGGER_NAME (bucket=$BUCKET_INPUT_FULL → workflow=$WORKFLOW_NAME)"
