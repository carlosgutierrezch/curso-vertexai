#!/bin/bash
# Ensambla el workflow, sustituye las URLs de las funciones desplegadas
# y despliega el workflow `cv-processing` en GCP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$ROOT_DIR/.env"

SUFFIX="${USER_SUFFIX:+-$USER_SUFFIX}"
WORKFLOW_NAME="cv-processing${SUFFIX}"

# 1. Ensamblar workflow_template + steps → workflow.yaml
echo "Ensamblando workflow.yaml..."
python3 "$SCRIPT_DIR/build_workflow.py"

# 2. Leer las URLs de las funciones desplegadas
echo "Recuperando URLs de las Cloud Functions..."
get_url() {
  local name="$1"
  gcloud functions describe "${name}${SUFFIX}" \
    --gen2 \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='value(serviceConfig.uri)'
}

VALIDATOR_URL="$(get_url validator)"
PARSER_URL="$(get_url parser)"
EXTRACTOR_URL="$(get_url extractor)"
LOADER_URL="$(get_url loader)"

echo "  validator → $VALIDATOR_URL"
echo "  parser    → $PARSER_URL"
echo "  extractor → $EXTRACTOR_URL"
echo "  loader    → $LOADER_URL"

# 3. Sustituir placeholders en el workflow.yaml ensamblado
WORKFLOW_FILE="$SCRIPT_DIR/workflow.yaml"
sed -i.bak -e "s|VALIDATOR_URL|${VALIDATOR_URL}|" "$WORKFLOW_FILE"
sed -i.bak -e "s|PARSER_URL|${PARSER_URL}|" "$WORKFLOW_FILE"
sed -i.bak -e "s|EXTRACTOR_URL|${EXTRACTOR_URL}|" "$WORKFLOW_FILE"
sed -i.bak -e "s|LOADER_URL|${LOADER_URL}|" "$WORKFLOW_FILE"
rm -f "${WORKFLOW_FILE}.bak"

# 4. Desplegar el workflow
echo "Desplegando workflow ${WORKFLOW_NAME}..."
gcloud workflows deploy "$WORKFLOW_NAME" \
  --source="$WORKFLOW_FILE" \
  --location="$REGION" \
  --project="$PROJECT_ID"

echo "Workflow desplegado: ${WORKFLOW_NAME}"
