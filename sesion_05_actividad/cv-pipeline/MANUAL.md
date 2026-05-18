# Manual paso a paso · cv-pipeline

> Guía para construir desde cero un pipeline serverless en GCP que procesa CVs.
> Pensada para seguir en clase. El resultado final es equivalente al que
> ya está en el repo — la diferencia es que aquí lo entiendes pieza a pieza.

## Qué vas a construir

```
[Recruiter sube CV]
        ↓
   cvs-input (Cloud Storage)
        ↓
   Eventarc detecta el objeto nuevo
        ↓
   Workflow "cv-processing"
        ├─→ validator   (¿es PDF/DOCX procesable?)
        ├─→ parser      (PDF/DOCX → Markdown)
        ├─→ extractor   (Markdown → JSON con Gemini)
        └─→ loader      (JSON → BigQuery)
```

Cada paso es una Cloud Function Gen2 (Python 3.11). El Workflow las llama
en orden con OIDC. Eventarc dispara el Workflow cuando aparece un objeto
nuevo en el bucket de entrada.

## Antes de empezar

Necesitas en tu máquina:

- Python 3.11 (`python3 --version`)
- Google Cloud SDK con `gcloud` y `bq` (`gcloud --version`)
- Un proyecto GCP con billing activo
- Tu cuenta autenticada y ADC configurada:

```sh
gcloud auth login
gcloud auth application-default login
gcloud config set project TU_PROJECT_ID
```

## Paso 0 · Clonar el repo y entrar

```sh
git clone https://github.com/carlosgutierrezch/curso-vertexai.git
cd curso-vertexai/sesion_05_actividad/cv-pipeline
```

A partir de aquí todos los comandos los ejecutas desde esta carpeta.

## Paso 1 · Configurar el entorno

```sh
cp .env.example .env
$EDITOR .env
```

Rellena:

| Variable | Valor |
|---|---|
| `PROJECT_ID` | El project ID de tu proyecto GCP |
| `REGION` | `europe-southwest1` (Madrid) |
| `USER_SUFFIX` | **Tu identificador único** (ej. `juan`, `ana01`) |

> **Por qué `USER_SUFFIX`**: los nombres de bucket en GCS son **globales**.
> Si dos compañeros usáis `cvs-input` sin sufijo, el segundo falla. El sufijo
> hace que tus recursos se llamen `cvs-input-juan`, `validator-juan`, etc.
> Máximo 16 caracteres (los nombres de Service Account tienen límite 30 y
> `cv-trigger-sa-<sufijo>` ya gasta 14).

## Paso 2 · Bootstrap del proyecto (APIs + IAM)

GCP necesita 11 APIs habilitadas y unos roles concedidos a la Service Account
que las Cloud Functions usarán por debajo. Esto lo hace `init.sh`:

```sh
bash infra/init.sh
```

Qué pasa por dentro:

- **`gcloud services enable`** de las 11 APIs (aiplatform, bigquery,
  cloudbuild, cloudfunctions, eventarc, run, storage, workflows, etc.).
- **`gcloud projects add-iam-policy-binding`** de 7 roles a la default
  Compute SA: cloudbuild.builds.builder, artifactregistry.writer,
  logging.logWriter, storage.objectAdmin, aiplatform.user,
  bigquery.dataEditor, bigquery.jobUser.

> **Por qué los roles**: en proyectos GCP creados desde mediados de 2024,
> Google bloquea el auto-grant de `roles/editor` a la default Compute SA
> (policy `iam.automaticIamGrantsForDefaultServiceAccounts`). Sin estos roles,
> el primer `gcloud functions deploy` falla con un error opaco:
> `Build failed: missing permission on the build service account`.

**Verificación**: deberías ver `OK (11 APIs habilitadas)` y `OK (7 roles asignados)`.

## Paso 3 · Crear los buckets

```sh
bash infra/deploy_buckets.sh
```

Crea 3 buckets en `europe-southwest1` con tu sufijo:

| Bucket | Para qué |
|---|---|
| `cvs-input-<sufijo>` | Donde el recruiter sube el CV original |
| `cvs-markdown-<sufijo>` | Markdown intermedio escrito por el parser |
| `cvs-json-<sufijo>` | JSON estructurado escrito por el extractor |

> **Por qué 3 buckets y no 1**: separación de responsabilidades. Cada función
> tiene su zona. Es más fácil debuggear (vas a `cvs-markdown` y ves
> exactamente qué le pasó el parser al extractor), aplicar políticas de
> retención distintas, y conceder permisos granulares por bucket.

**Verificación**:

```sh
gcloud storage ls
# Deberías ver gs://cvs-input-<sufijo>, gs://cvs-markdown-<sufijo>, gs://cvs-json-<sufijo>
```

## Paso 4 · Tu 1ª Cloud Function: `validator`

### 4.1 Estructura

Cada función vive en su propia carpeta con 3 archivos:

```
functions/validator/
├── main.py            ← código Python
├── requirements.txt   ← dependencias
└── deploy.sh          ← script de despliegue con gcloud
```

### 4.2 El código (`functions/validator/main.py`)

Sigue el **patrón clase-servicio**: una clase con la lógica, y un handler
HTTP top-level que delega.

```python
"""Cloud Function: validator.

Recibe {bucket, file} y comprueba si el objeto es procesable.
Respuesta: {"valid": bool, "reason": str}
"""

import logging
import os
from typing import Optional

import functions_framework
from google.cloud import storage


class Validator:
    """Comprueba que un objeto de GCS es un CV procesable."""

    def __init__(self):
        self.min_size_bytes = int(os.getenv("MIN_SIZE_BYTES", "1024"))
        self.max_size_bytes = int(os.getenv("MAX_SIZE_BYTES", str(10 * 1024 * 1024)))
        self.allowed_extensions = {".pdf", ".docx"}
        self.storage_client = storage.Client()
        self.logger = logging.getLogger(self.__class__.__name__)

    def validate(self, bucket_name: str, file_name: str) -> dict:
        blob = self.storage_client.bucket(bucket_name).get_blob(file_name)
        if blob is None:
            return {"valid": False, "reason": f"object gs://{bucket_name}/{file_name} not found"}

        extension = os.path.splitext(file_name)[1].lower()
        if extension not in self.allowed_extensions:
            return {"valid": False, "reason": f"extension {extension!r} not allowed"}

        size = blob.size or 0
        if size < self.min_size_bytes:
            return {"valid": False, "reason": f"file too small: {size} bytes"}
        if size > self.max_size_bytes:
            return {"valid": False, "reason": f"file too large: {size} bytes"}

        return {"valid": True, "reason": "ok", "size": size}


# Singleton lazy: una instancia por contenedor (warm starts reusan)
_validator: Optional[Validator] = None

def _get_validator() -> Validator:
    global _validator
    if _validator is None:
        _validator = Validator()
    return _validator


@functions_framework.http
def validate(request):
    payload = request.get_json(silent=True) or {}
    bucket_name = payload.get("bucket")
    file_name = payload.get("file")
    if not bucket_name or not file_name:
        return {"valid": False, "reason": "missing bucket or file"}, 400
    return _get_validator().validate(bucket_name, file_name)
```

> **Por qué clase + singleton + handler fino**:
> - **Clase**: encapsula config + cliente GCS + lógica. Testeable.
> - **Singleton lazy**: la primera invocación paga el cold start (instancia
>   y cliente GCS); las warm starts reutilizan. Si pones todo en module-load,
>   el cold start es más lento; si lo pones dentro del handler, pagas cada vez.
> - **Handler fino**: separa transporte HTTP de lógica de dominio.

### 4.3 Dependencias (`functions/validator/requirements.txt`)

```
functions-framework==3.*
google-cloud-storage==2.*
```

### 4.4 Script de despliegue (`functions/validator/deploy.sh`)

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$ROOT_DIR/.env"

SERVICE_NAME="validator${USER_SUFFIX:+-$USER_SUFFIX}"

gcloud functions deploy "$SERVICE_NAME" \
  --gen2 \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --runtime=python311 \
  --source="$SCRIPT_DIR" \
  --entry-point=validate \
  --trigger-http \
  --allow-unauthenticated
```

> **Por qué `--allow-unauthenticated`**: el codelab original lo deja así
> por simplicidad. El Workflow llamará con OIDC, pero las funciones aceptan
> cualquier llamada. Para producción real: quitar el flag y conceder
> `roles/run.invoker` al SA del Workflow.

### 4.5 Desplegar

```sh
chmod +x functions/validator/deploy.sh
bash functions/validator/deploy.sh
```

Tarda ~2-3 min. Al final verás la URL de la función desplegada.

> **Si falla con `missing permission on the build service account`**:
> espera 60s (propagación IAM tras `init.sh`) y reintenta.

### 4.6 Probarla

```sh
# Sube un fichero pequeño cualquiera al bucket de entrada
echo "dummy" > /tmp/small.txt
gcloud storage cp /tmp/small.txt gs://cvs-input-$USER_SUFFIX/

# Llama directamente a la función (no via workflow todavía)
VALIDATOR_URL=$(gcloud functions describe validator-$USER_SUFFIX \
  --gen2 --region=$REGION --format='value(serviceConfig.uri)')

curl -X POST "$VALIDATOR_URL" \
  -H 'Content-Type: application/json' \
  -d "{\"bucket\":\"cvs-input-$USER_SUFFIX\",\"file\":\"small.txt\"}"
# Debe devolver: {"valid": false, "reason": "extension '.txt' not allowed"}
```

## Paso 5 · 2ª Cloud Function: `parser`

Mismo patrón. Cambian dos cosas:

1. Necesita **dos dependencias más**: `pypdf` para PDFs y `python-docx` para DOCX.
2. El `deploy.sh` añade `--set-env-vars=MARKDOWN_BUCKET=...` para saber dónde
   escribir el resultado.

Archivos completos en `functions/parser/`. Estructura del `main.py`:

```python
class Parser:
    def __init__(self):
        self.markdown_bucket = os.environ["MARKDOWN_BUCKET"]
        self.storage_client = storage.Client()
        ...

    def parse(self, bucket_name: str, file_name: str) -> dict:
        # 1. Descarga bytes del bucket de entrada
        # 2. Si .pdf → self._pdf_to_markdown(bytes)
        # 3. Si .docx → self._docx_to_markdown(bytes)
        # 4. Sube el resultado a self.markdown_bucket
        # 5. Devuelve {"bucket": ..., "file": ...} del .md generado
        ...

    def _pdf_to_markdown(self, data: bytes) -> str:
        # Usa pypdf.PdfReader
        ...

    def _docx_to_markdown(self, data: bytes) -> str:
        # Usa docx.Document
        ...
```

Desplegar:

```sh
bash functions/parser/deploy.sh
```

## Paso 6 · 3ª Cloud Function: `extractor`

Aquí entra **Vertex AI Gemini** con structured output. La función:

1. Descarga el `.md` que el parser generó.
2. Llama a Gemini con un `response_schema` de Pydantic (estructura forzada).
3. Sube el JSON resultante a `cvs-json`.

Patrón:

```python
from google import genai
from google.genai import types
from pydantic import BaseModel

class ExtractedCV(BaseModel):
    nombre: str | None = None
    email: str | None = None
    telefono: str | None = None
    anios_experiencia: float | None = None
    skills: list[str] = []
    ultima_empresa: str | None = None

SYSTEM_PROMPT = "Eres un extractor de datos de CVs..."

class Extractor:
    def __init__(self):
        self.json_bucket = os.environ["JSON_BUCKET"]
        self.project_id = os.environ["PROJECT_ID"]
        self.region = os.environ["REGION"]
        # Sin API keys: usa ADC (la SA de la Cloud Function)
        self.genai_client = genai.Client(
            vertexai=True, project=self.project_id, location=self.region
        )

    def extract(self, bucket_name: str, file_name: str) -> dict:
        markdown = self.storage_client.bucket(bucket_name).get_blob(file_name).download_as_text()

        response = self.genai_client.models.generate_content(
            model="gemini-2.5-flash",
            contents=markdown,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_PROMPT,
                response_mime_type="application/json",
                response_schema=ExtractedCV,   # ← schema forzado
                temperature=0.0,
            ),
        )
        extracted = response.parsed.model_dump()
        # subir a cvs-json
        ...
        return {"bucket": self.json_bucket, "file": f"{base}.json"}
```

> **Por qué `response_schema=ExtractedCV`**: fuerza al modelo a devolver
> JSON con exactamente la estructura definida. Gemini valida internamente
> antes de responder. Sin esto te tocaría hacer `json.loads` + try/except
> + validación manual a posteriori.

> **Por qué Vertex AI y no OpenAI**: cero API keys (ADC autentica con la
> SA de la función), coherente con un curso de GCP, los datos no salen
> de tu proyecto.

Desplegar:

```sh
bash functions/extractor/deploy.sh
```

## Paso 7 · 4ª Cloud Function: `loader`

Lee el `.json`, le añade `source_file` y `processed_at`, e inserta en
BigQuery. **Patrón auto-curativo**: si la tabla no existe, la crea con DDL.

```python
TABLE_SCHEMA_DDL = """
CREATE SCHEMA IF NOT EXISTS `{project}.{dataset}`
  OPTIONS(location="{location}");

CREATE TABLE IF NOT EXISTS `{project}.{dataset}.{table}` (
  nombre            STRING,
  email             STRING,
  telefono          STRING,
  anios_experiencia FLOAT64,
  skills            ARRAY<STRING>,
  ultima_empresa    STRING,
  source_file       STRING,
  processed_at      TIMESTAMP
);
"""

class Loader:
    def __init__(self):
        self.bq_dataset = os.environ["BQ_DATASET"]
        self.bq_table = os.environ["BQ_TABLE"]
        self.bq_location = os.environ["BQ_LOCATION"]
        self.bq_client = bigquery.Client()
        self._table_ensured = False  # ← cache cold-start

    def load(self, bucket_name: str, file_name: str) -> dict:
        row = json.loads(self.storage_client.bucket(bucket_name).get_blob(file_name).download_as_text())
        row["source_file"] = file_name
        row["processed_at"] = datetime.now(timezone.utc).isoformat()
        table_id = self._ensure_table()
        errors = self.bq_client.insert_rows_json(table_id, [row])
        return {"ok": not errors, "row": file_name}

    def _ensure_table(self) -> str:
        if self._table_ensured:
            return f"{self.bq_client.project}.{self.bq_dataset}.{self.bq_table}"
        ddl = TABLE_SCHEMA_DDL.format(...)
        self.bq_client.query(ddl, location=self.bq_location).result()
        self._table_ensured = True
        ...
```

> **Por qué DDL idempotente en el código y no script aparte**:
> auto-curativo. Si alguien borra la tabla por error, la siguiente
> ejecución del loader la recrea. Si vienes de un proyecto nuevo,
> no necesitas pasos previos de "crea el dataset". `CREATE SCHEMA/TABLE
> IF NOT EXISTS` es ~300 ms en el cold start y free en los warm starts.

Desplegar:

```sh
bash functions/loader/deploy.sh
```

## Paso 8 · El Workflow que orquesta las 4 funciones

Hasta ahora tienes 4 funciones HTTP independientes. Falta el orquestador
que las llama en orden.

### 8.1 Estructura modular

En lugar de un único `workflow.yaml` monolítico, usamos un **template +
fragmentos**:

```
infra/
├── workflow_template.yaml   ← esqueleto con marcador __PIPELINE_STEPS__
├── steps/
│   ├── 10_validate.yaml
│   ├── 20_parse.yaml
│   ├── 30_extract.yaml
│   └── 40_load.yaml
└── build_workflow.py        ← junta template + steps en workflow.yaml
```

> **Por qué partido**: añadir/quitar un paso es editar un fragmento, no
> diff'ear un YAML largo. Útil cuando un alumno propone añadir un step
> (lo veremos en el Paso 11).

### 8.2 El template (`infra/workflow_template.yaml`)

```yaml
main:
  params: [event]
  steps:
  - log_event:
      call: sys.log
      args:
          text: ${event}
          severity: INFO
  - extract_bucket_and_file:
      assign:
      - bucket: ${event.data.bucket}
      - file: ${event.data.name}
  # __PIPELINE_STEPS__
  - final:
      return:
        validate: ${validateResponse.code}
        parse: ${parseResponse.code}
        extract: ${extractResponse.code}
        load: ${loadResponse.code}
```

El marcador `# __PIPELINE_STEPS__` se sustituye al ensamblar.

### 8.3 Un step (`infra/steps/10_validate.yaml`)

```yaml
  - validate:
      call: http.post
      args:
        url: VALIDATOR_URL # TODO: Replace
        auth:
          type: OIDC
        body:
            bucket: ${bucket}
            file: ${file}
      result: validateResponse
  - check_valid:
      switch:
        - condition: ${validateResponse.body.valid == true}
          next: parse
      next: end
```

> **`auth: type: OIDC`**: el Workflow firma cada `http.post` con su SA.
> Si las funciones requirieran auth, este token serviría para entrar.
> Con `--allow-unauthenticated` no es necesario, pero el campo ya está
> preparado.

### 8.4 Desplegar el workflow

```sh
bash infra/deploy_workflow.sh
```

Qué hace:

1. `python3 infra/build_workflow.py` → genera `workflow.yaml` (template + 4 steps).
2. `gcloud functions describe ...` → recupera las URLs reales de las 4 funciones.
3. `sed` → sustituye `VALIDATOR_URL`, `PARSER_URL`, etc. en el YAML.
4. `gcloud workflows deploy cv-processing-<sufijo>` → publica el workflow.

## Paso 9 · El trigger Eventarc que une todo

Hasta ahora el Workflow existe pero nadie lo invoca. El último paso es
**conectar GCS → Workflow** vía Eventarc.

```sh
bash infra/deploy_trigger.sh
```

Qué hace (siguiendo el codelab):

1. Crea una **Service Account** `cv-trigger-sa-<sufijo>`.
2. Le concede:
   - `roles/workflows.invoker` (poder invocar workflows).
   - `roles/eventarc.eventReceiver` (poder recibir eventos).
3. Concede `roles/pubsub.publisher` al **SA del servicio de Cloud Storage**
   (Eventarc usa Pub/Sub internamente para entregar eventos de GCS).
4. Crea el **trigger Eventarc** con el filtro:
   - `type=google.cloud.storage.object.v1.finalized`
   - `bucket=cvs-input-<sufijo>`
   - Destino: `cv-processing-<sufijo>`

A partir de aquí, cada vez que aparezca un objeto nuevo en
`gs://cvs-input-<sufijo>/`, el Workflow se ejecuta automáticamente.

## Paso 10 · Verificar el pipeline funcionando end-to-end

```sh
# 1. Sube un CV (PDF o DOCX) al bucket de entrada
gcloud storage cp /ruta/a/tu_cv.pdf gs://cvs-input-$USER_SUFFIX/

# 2. Ver la última ejecución del workflow (espera ~30s)
gcloud workflows executions list cv-processing-$USER_SUFFIX \
  --location=$REGION --limit=1

# 3. Si el estado es SUCCEEDED, verifica que llegó a BigQuery
bq query --use_legacy_sql=false \
  "SELECT * FROM \`$PROJECT_ID.cvs.processed\` ORDER BY processed_at DESC LIMIT 1"
```

Si todo va bien, ves tu CV convertido en una fila estructurada con
nombre, email, skills, años de experiencia, etc.

## Paso 11 · Añadir tu propia función al pipeline

Imagina que quieres añadir un paso **`enricher`** que llama a una API
externa (LinkedIn, Crunchbase, lo que sea) para enriquecer el JSON antes
de cargarlo a BigQuery. Pipeline objetivo:

```
validator → parser → extractor → enricher → loader
```

Estos son los **5 pasos** que tienes que dar:

### 11.1 Crear la carpeta de la función

```sh
mkdir -p functions/enricher
cd functions/enricher
```

Copia los 3 archivos base de una función similar (ej. `extractor`):

```sh
cp ../extractor/{main.py,requirements.txt,deploy.sh} .
```

### 11.2 Editar `main.py`

Cambia el nombre de la clase, el handler, los env vars que necesite, y la
lógica del método principal. Mantén el patrón: clase + singleton lazy +
handler fino.

```python
class Enricher:
    def __init__(self):
        self.json_bucket = os.environ["JSON_BUCKET"]
        # ...

    def enrich(self, bucket_name: str, file_name: str) -> dict:
        # 1. Descarga el .json existente
        # 2. Llama a tu API externa
        # 3. Fusiona los datos
        # 4. Sobrescribe (o sube como _enriched.json)
        return {"bucket": ..., "file": ...}

_enricher = None
def _get_enricher():
    global _enricher
    if _enricher is None:
        _enricher = Enricher()
    return _enricher

@functions_framework.http
def enrich(request):
    payload = request.get_json(silent=True) or {}
    return _get_enricher().enrich(payload["bucket"], payload["file"])
```

### 11.3 Editar `requirements.txt`

Añade las deps que necesite (ej. `requests`, `httpx`, etc.).

### 11.4 Editar `deploy.sh`

Cambia:
- `SERVICE_NAME="enricher${USER_SUFFIX:+-$USER_SUFFIX}"`
- `--entry-point=enrich`
- `--set-env-vars=...` con los env vars que use

Despliégala:

```sh
bash functions/enricher/deploy.sh
```

### 11.5 Crear el fragmento del Workflow

Añade `infra/steps/35_enrich.yaml` (el 35 lo coloca entre extract y load):

```yaml
  - enrich:
      call: http.post
      args:
        url: ENRICHER_URL # TODO: Replace
        auth:
          type: OIDC
        body:
            bucket: ${extractResponse.body.bucket}
            file: ${extractResponse.body.file}
      result: enrichResponse
```

### 11.6 Modificar el paso siguiente

El step `40_load.yaml` actualmente lee del `extractResponse`. Cámbialo
para leer del `enrichResponse`:

```yaml
  - load:
      call: http.post
      args:
        url: LOADER_URL # TODO: Replace
        auth:
          type: OIDC
        body:
            bucket: ${enrichResponse.body.bucket}   # ← antes: extractResponse
            file: ${enrichResponse.body.file}
      result: loadResponse
```

### 11.7 Añadir la URL del enricher al `deploy_workflow.sh`

Edita `infra/deploy_workflow.sh` para incluir tu nueva función en la
sustitución de URLs:

```bash
ENRICHER_URL="$(get_url enricher)"
echo "  enricher  → $ENRICHER_URL"

sed -i.bak -e "s|ENRICHER_URL|${ENRICHER_URL}|" "$WORKFLOW_FILE"
```

### 11.8 Reensamblar y redesplegar el workflow

```sh
bash infra/deploy_workflow.sh
```

`build_workflow.py` concatena los `steps/*.yaml` por orden alfabético,
así que tu `35_enrich.yaml` queda entre `30_extract.yaml` y `40_load.yaml`
sin que tengas que tocar el template.

### 11.9 Probar

Sube un CV nuevo, espera la ejecución, y verifica en BQ que aparece la fila
con los campos enriquecidos.

## Troubleshooting

| Síntoma | Causa | Fix |
|---|---|---|
| `Build failed: missing permission on the build service account` justo tras `init.sh` | Propagación IAM | Espera 60s y reintenta el deploy |
| `Bucket name already exists` | `USER_SUFFIX` duplicado o vacío | Cambia tu `USER_SUFFIX` en `.env` |
| `Service account ID does not have a length between 6 and 30` | `USER_SUFFIX` demasiado largo | Acórtalo (máx 16 chars) |
| Workflow stuck en `ACTIVE` mucho tiempo | Alguna función falla | `gcloud workflows executions describe <id> --workflow=cv-processing-<sufijo>` para ver qué step |
| Extractor devuelve JSON vacío | PDF escaneado, `pypdf` no hace OCR | Usar Document AI o pasar el PDF directo a Gemini multimodal |
| Trigger no se dispara | Permisos de la SA de Storage | Revisa que `roles/pubsub.publisher` esté concedido (lo hace `deploy_trigger.sh`) |

## Limpieza al terminar

Cuando termines la clase y no quieras seguir pagando recursos:

```sh
bash infra/cleanup.sh
```

Borra trigger, workflow, 4 funciones, 3 buckets (con contenido), dataset BQ
(con tablas) y la SA del trigger. NO deshabilita APIs ni revoca roles IAM
(podrían estar en uso por otros recursos del proyecto).

## Para profundizar

- README.md del repo: comandos rápidos y arquitectura
- `simulate_local.py`: ejecuta las 3 fases sin desplegar (útil para iterar prompts)
- Codelab oficial: [Crea una organización basada en eventos con Eventarc y Workflows](https://codelabs.developers.google.com/codelabs/cloud-event-driven-orchestration?hl=es-419)
