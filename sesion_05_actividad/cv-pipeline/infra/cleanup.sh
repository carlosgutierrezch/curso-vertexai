#!/bin/bash
# Teardown del pipeline cv-pipeline. Borra TODOS los recursos creados,
# en orden inverso de dependencias. Idempotente: skip si no existe.
#
# Borra: trigger Eventarc, workflow, 4 Cloud Functions, 3 buckets (con objetos),
#        SA del trigger, dataset BigQuery (con tablas).
#
# NO borra: los roles IAM concedidos a la default Compute SA (los deja por si
#           hay otros recursos en el proyecto que los usan).
# NO deshabilita APIs (lo mismo).
set -uo pipefail  # sin -e: queremos seguir aunque algo falle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$ROOT_DIR/.env"

SUFFIX="${USER_SUFFIX:+-$USER_SUFFIX}"
TRIGGER_NAME="trigger-cv-processing${SUFFIX}"
WORKFLOW_NAME="cv-processing${SUFFIX}"
SA_NAME="cv-trigger-sa${SUFFIX}"

echo "════════════════════════════════════════════════════════════"
echo " cv-pipeline · teardown"
echo "════════════════════════════════════════════════════════════"
read -r -p "Vas a borrar todos los recursos del pipeline en $PROJECT_ID. ¿Continuar? [y/N] " yn
case "$yn" in [Yy]*) ;; *) echo "Cancelado"; exit 0;; esac

# 1. Trigger Eventarc
echo ""
echo "▸ Borrando trigger $TRIGGER_NAME..."
gcloud eventarc triggers delete "$TRIGGER_NAME" \
  --location="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || echo "  (no existía)"

# 2. Workflow
echo "▸ Borrando workflow $WORKFLOW_NAME..."
gcloud workflows delete "$WORKFLOW_NAME" \
  --location="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || echo "  (no existía)"

# 3. Cloud Functions
for FN in validator parser extractor loader; do
  SVC="${FN}${SUFFIX}"
  echo "▸ Borrando función $SVC..."
  gcloud functions delete "$SVC" --gen2 \
    --region="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || echo "  (no existía)"
done

# 4. SA del trigger
echo "▸ Borrando service account $SA_NAME..."
gcloud iam service-accounts delete "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" --quiet 2>/dev/null || echo "  (no existía)"

# 5. Buckets (con todo su contenido)
for BUCKET in "$BUCKET_INPUT" "$BUCKET_MARKDOWN" "$BUCKET_JSON"; do
  NAME="${BUCKET}${SUFFIX}"
  echo "▸ Borrando bucket gs://${NAME} y todo su contenido..."
  gcloud storage rm --recursive "gs://${NAME}" --project="$PROJECT_ID" --quiet 2>/dev/null \
    || echo "  (no existía)"
done

# 6. Dataset BigQuery (con tablas)
echo "▸ Borrando dataset ${BQ_DATASET}..."
bq rm -r -f --project_id="$PROJECT_ID" "${BQ_DATASET}" 2>/dev/null \
  || echo "  (no existía)"

echo ""
echo "════════════════════════════════════════════════════════════"
echo " ✅ cleanup completo"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "No se han borrado:"
echo "  - APIs habilitadas (déjalas, no cuestan)"
echo "  - Roles IAM en la default Compute SA (afectan a todo el proyecto)"
