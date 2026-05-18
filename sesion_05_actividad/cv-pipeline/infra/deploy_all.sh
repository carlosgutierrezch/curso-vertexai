#!/bin/bash
# Despliegue end-to-end del pipeline cv-pipeline.
# Ejecuta toda la secuencia en orden. Idempotente: seguro reejecutar.
#
# Tiempo aproximado en proyecto limpio: ~15 min (cuatro builds de Cloud Function
# en paralelo + workflow + trigger).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "════════════════════════════════════════════════════════════"
echo " cv-pipeline · despliegue end-to-end"
echo "════════════════════════════════════════════════════════════"

echo ""
echo "▸ [1/4] Bootstrap (APIs + IAM)"
bash "$SCRIPT_DIR/init.sh"

echo ""
echo "▸ [2/4] Crear buckets"
bash "$SCRIPT_DIR/deploy_buckets.sh"

echo ""
echo "▸ [3/4] Desplegar las 4 Cloud Functions en paralelo"
bash "$ROOT_DIR/functions/validator/deploy.sh" >/tmp/cv-pipeline-validator.log 2>&1 &
PID_V=$!
bash "$ROOT_DIR/functions/parser/deploy.sh"    >/tmp/cv-pipeline-parser.log    2>&1 &
PID_P=$!
bash "$ROOT_DIR/functions/extractor/deploy.sh" >/tmp/cv-pipeline-extractor.log 2>&1 &
PID_E=$!
bash "$ROOT_DIR/functions/loader/deploy.sh"    >/tmp/cv-pipeline-loader.log    2>&1 &
PID_L=$!

echo "  (4 deploys lanzados — logs en /tmp/cv-pipeline-*.log)"
echo "  esperando a que terminen..."

FAILED=0
wait $PID_V || { echo "  ✗ validator falló — ver /tmp/cv-pipeline-validator.log"; FAILED=1; }
echo "  ✓ validator"
wait $PID_P || { echo "  ✗ parser falló — ver /tmp/cv-pipeline-parser.log"; FAILED=1; }
echo "  ✓ parser"
wait $PID_E || { echo "  ✗ extractor falló — ver /tmp/cv-pipeline-extractor.log"; FAILED=1; }
echo "  ✓ extractor"
wait $PID_L || { echo "  ✗ loader falló — ver /tmp/cv-pipeline-loader.log"; FAILED=1; }
echo "  ✓ loader"

if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "Alguno de los deploys falló. Revisa los logs y reejecuta este script."
  echo "Si el error es 'missing permission on the build service account',"
  echo "espera 60s — la propagación IAM tarda."
  exit 1
fi

echo ""
echo "▸ [4/4] Workflow + Eventarc trigger"
bash "$SCRIPT_DIR/deploy_workflow.sh"
bash "$SCRIPT_DIR/deploy_trigger.sh"

echo ""
echo "════════════════════════════════════════════════════════════"
echo " ✅ cv-pipeline desplegado"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Próximo paso — prueba end-to-end:"
echo ""
# shellcheck disable=SC1091
source "$ROOT_DIR/.env"
SUFFIX="${USER_SUFFIX:+-$USER_SUFFIX}"
echo "  gcloud storage cp /ruta/al/cv.pdf gs://${BUCKET_INPUT}${SUFFIX}/"
echo ""
echo "  # Ver ejecución del workflow:"
echo "  gcloud workflows executions list cv-processing${SUFFIX} \\"
echo "    --location=$REGION --limit=1"
echo ""
echo "  # Verificar fila en BigQuery:"
echo "  bq query --use_legacy_sql=false \\"
echo "    'SELECT * FROM \`${PROJECT_ID}.${BQ_DATASET}.${BQ_TABLE}\` ORDER BY processed_at DESC LIMIT 1'"
