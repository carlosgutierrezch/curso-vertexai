#!/bin/bash
# Bootstrap idempotente del proyecto GCP para cv-pipeline.
#
# Hace dos cosas, ambas idempotentes (seguro reejecutar tantas veces como
# quieras):
#   1. Habilita las 11 APIs requeridas.
#   2. Concede a la default Compute SA los 7 roles necesarios para que
#      Cloud Functions Gen2 pueda buildear y ejecutarse, y para que el
#      pipeline pueda hablar con GCS, BigQuery y Vertex AI.
#
# Requiere credenciales de admin del proyecto (roles/owner o equivalente).
#
# Por qué no está dentro del workflow: bootstrap problem. El workflow no puede
# arrancar sin workflows.googleapis.com; las funciones no pueden desplegarse
# sin cloudfunctions.googleapis.com. La habilitación tiene que pasar ANTES
# de que exista runtime alguno donde colgar el check.
#
# Por qué los roles IAM aquí y no out-of-the-box: en proyectos GCP creados
# después de ~mediados de 2024, Google bloquea el auto-grant de roles/editor
# a la default Compute SA (policy iam.automaticIamGrantsForDefaultServiceAccounts).
# Sin estos roles, el primer `gcloud functions deploy` falla con
# "missing permission on the build service account". Diagnóstico opaco;
# mejor preconceder.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$ROOT_DIR/.env"

echo "=== Bootstrap GCP para cv-pipeline ==="
echo "Proyecto: $PROJECT_ID"
echo "Región:   $REGION"
echo ""

# ── 1. Habilitar APIs (idempotente) ──
APIS=(
  aiplatform.googleapis.com           # Vertex AI Gemini (extractor)
  artifactregistry.googleapis.com     # Imágenes de las Cloud Functions Gen2
  bigquery.googleapis.com             # Loader
  cloudbuild.googleapis.com           # Build de las Cloud Functions
  cloudfunctions.googleapis.com       # 4 funciones
  eventarc.googleapis.com             # Trigger GCS → Workflows
  pubsub.googleapis.com               # Eventarc usa Pub/Sub internamente
  run.googleapis.com                  # Cloud Functions Gen2 = Cloud Run
  storage.googleapis.com              # 3 buckets
  workflows.googleapis.com            # Orquestador
  workflowexecutions.googleapis.com   # Ejecutar workflows
)

echo "[1/2] Habilitando APIs..."
gcloud services enable "${APIS[@]}" --project="$PROJECT_ID"
echo "OK (${#APIS[@]} APIs habilitadas)"
echo ""

# ── 2. Asignar roles IAM a la default Compute SA (idempotente) ──
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

ROLES=(
  roles/cloudbuild.builds.builder   # Cloud Build necesita esto para construir las funciones
  roles/artifactregistry.writer     # Almacenar la imagen construida
  roles/logging.logWriter           # Logs del build y del runtime
  roles/storage.objectAdmin         # parser/extractor leen y escriben en los 3 buckets
  roles/aiplatform.user             # extractor llama a Vertex AI Gemini
  roles/bigquery.dataEditor         # loader hace INSERT
  roles/bigquery.jobUser            # loader ejecuta DDL (CREATE SCHEMA/TABLE)
)

echo "[2/2] Asignando roles a $COMPUTE_SA..."
for ROLE in "${ROLES[@]}"; do
  echo "  → $ROLE"
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --role="$ROLE" \
    --member="serviceAccount:$COMPUTE_SA" \
    --condition=None \
    --quiet >/dev/null
done
echo "OK (${#ROLES[@]} roles asignados)"
echo ""

echo "=== Init completado ==="
echo "Nota: la propagación IAM puede tardar 1-2 min. Si el primer deploy de"
echo "Cloud Function falla con 'missing permission on the build service account',"
echo "espera 60s y reintenta."
echo ""
echo "Siguiente paso: bash infra/deploy_buckets.sh  (o bash infra/deploy_all.sh)"
