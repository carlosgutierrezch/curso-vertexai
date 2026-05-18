# cv-pipeline

Pipeline serverless en Google Cloud que procesa CVs end-to-end:
**PDF/DOCX → Markdown → JSON estructurado → BigQuery**.

Inspirado en el codelab oficial de Google [Crea una organización basada en
eventos con Eventarc y Workflows](https://codelabs.developers.google.com/codelabs/cloud-event-driven-orchestration?hl=es-419),
adaptado a procesamiento documental con Vertex AI Gemini.

> **¿Primera vez?** Sigue el [MANUAL paso a paso](MANUAL.md) — guía
> pedagógica que construye cada función desde cero, ideal para clase.
> Este README es la referencia rápida para quien ya conoce el pipeline.

## Arquitectura

```
              CV Processing Pipeline · Eventarc + Workflows

  👤              Cloud Storage Trigger
HR Recruiter     (Eventarc)
     │                  │
     │ upload           ▼
     ▼          ┌─────────────┐    ┌─────────────┐     ┌──{ }─ Validator
┌──────────┐    │ cvs-input   │───▶│ CV          │────▶│  ┌──{ }─ Parser
│ CV.pdf   │───▶│ Cloud       │    │ Processing  │     │  ├──{ }─ Extractor
│ CV.docx  │    │ Storage     │    │ (Workflows) │     │  └──{ }─ Loader
└──────────┘    └─────────────┘    └─────────────┘     └──────────────────
                                                                │
       ┌─── cvs-markdown ◄── (parser escribe)                   │
       │    Cloud Storage                                       │
       │                                                        │
       └─── cvs-json ◄── (extractor escribe) ──┐                │
            Cloud Storage                       │                │
                                                ▼                ▼
                                        ┌────────────────┐ ┌────────────────┐
                                        │ Vertex AI      │ │ cvs.processed  │
                                        │ Gemini 2.5     │ │ BigQuery       │
                                        │ Flash          │ │                │
                                        └────────────────┘ └────────────────┘
```

| Fase | Función | Input | Output |
|---|---|---|---|
| 1 | `validator` | `{bucket, file}` | `{valid, reason}` — comprueba ext + tamaño |
| 2 | `parser` | `{bucket, file}` | `{bucket, file}` del `.md` — pypdf + python-docx |
| 3 | `extractor` | `{bucket, file}` del `.md` | `{bucket, file}` del `.json` — Gemini structured output |
| 4 | `loader` | `{bucket, file}` del `.json` | `{ok, row}` — DDL idempotente + `insert_rows_json` |

Las 4 son Cloud Functions Gen2 Python 3.11, llamadas con OIDC desde el Workflow.
El `loader` ejecuta `CREATE SCHEMA / TABLE IF NOT EXISTS` en su cold start —
no necesitas crear la tabla de BigQuery a mano.

## Prerequisites

- Python 3.11+ (`python3 --version`)
- Google Cloud SDK con `gcloud` y `bq` (`gcloud --version`)
- Proyecto GCP con billing activado
- Tu cuenta autenticada con permisos de admin sobre el proyecto:
  ```sh
  gcloud auth login
  gcloud auth application-default login
  gcloud config set project TU_PROJECT_ID
  ```
- Editar a mano el `.env` (no se rellena solo)

## Despliegue rápido

```sh
# 1. Configurar el entorno
cp .env.example .env
$EDITOR .env                       # rellenar PROJECT_ID y USER_SUFFIX

# 2. Bootstrap + buckets + 4 funciones + workflow + trigger (~15 min)
bash infra/deploy_all.sh

# 3. Probar end-to-end
gcloud storage cp tu_cv.pdf gs://cvs-input-<USER_SUFFIX>/

# 4. Verificar
bq query --use_legacy_sql=false \
  'SELECT * FROM `TU_PROJECT_ID.cvs.processed` ORDER BY processed_at DESC LIMIT 1'
```

## Despliegue paso a paso (alternativa pedagógica)

Si prefieres ver qué hace cada parte:

```sh
bash infra/init.sh                          # APIs + IAM en la default Compute SA
bash infra/deploy_buckets.sh                # 3 buckets en europe-southwest1
bash functions/validator/deploy.sh          # ~3 min cada uno
bash functions/parser/deploy.sh
bash functions/extractor/deploy.sh
bash functions/loader/deploy.sh
bash infra/deploy_workflow.sh               # ensambla + sustituye URLs + despliega
bash infra/deploy_trigger.sh                # SA + roles + trigger Eventarc
```

## Variables de entorno (`.env`)

| Variable | Ejemplo | Para qué |
|---|---|---|
| `PROJECT_ID` | `mi-proyecto-gcp` | Proyecto donde se despliega todo |
| `REGION` | `europe-southwest1` | Madrid. Para GDPR/People Analytics |
| `BUCKET_INPUT` | `cvs-input` | Bucket de entrada (sube CVs aquí) |
| `BUCKET_MARKDOWN` | `cvs-markdown` | Markdown intermedio |
| `BUCKET_JSON` | `cvs-json` | JSON estructurado |
| `BQ_DATASET` | `cvs` | Dataset de BigQuery |
| `BQ_TABLE` | `processed` | Tabla destino |
| `USER_SUFFIX` | `alumno01` | **Sufijo único por persona** — evita colisiones globales de nombres de bucket |

> **USER_SUFFIX es importante**: los nombres de bucket son globales en GCP.
> Si dos compañeros usáis `cvs-input` sin sufijo, el segundo falla. Convención:
> usa tu nombre de pila + número, o las 8 primeras chars del project hash.
> Máximo 16 chars (los nombres de SA tienen límite 30 y `cv-trigger-sa-<sufijo>`
> ya gasta 14).

## Estructura del repo

```
cv-pipeline/
├── README.md
├── pyproject.toml
├── .env.example                  ← plantilla; copiar a .env
├── .gitignore
├── infra/
│   ├── init.sh                   ← bootstrap (APIs + IAM)
│   ├── deploy_buckets.sh         ← crea los 3 buckets
│   ├── deploy_workflow.sh        ← ensambla workflow.yaml + despliega
│   ├── deploy_trigger.sh         ← SA + roles + trigger Eventarc
│   ├── deploy_all.sh             ← orquesta todo lo de arriba
│   ├── cleanup.sh                ← teardown idempotente
│   ├── build_workflow.py         ← concatena steps en workflow.yaml
│   ├── workflow_template.yaml    ← esqueleto con marcador __PIPELINE_STEPS__
│   ├── workflow.yaml             ← generado (gitignored)
│   └── steps/
│       ├── 10_validate.yaml      ← cada paso del workflow en su fragmento
│       ├── 20_parse.yaml
│       ├── 30_extract.yaml
│       └── 40_load.yaml
├── functions/
│   ├── validator/                ← cada función: main.py + requirements.txt + deploy.sh
│   ├── parser/
│   ├── extractor/
│   └── loader/
├── tests/                        ← tests mínimos de importabilidad
└── simulate_local.py             ← runner local de las 3 fases (opcional, debug)
```

## Probar localmente sin desplegar

Útil para iterar prompts del extractor o ajustar el parser sin esperar 3 min
por build:

```sh
python3 -m venv .venv
.venv/bin/pip install -r functions/parser/requirements.txt \
                     -r functions/extractor/requirements.txt \
                     -r functions/loader/requirements.txt
.venv/bin/python simulate_local.py /ruta/a/cv.pdf
```

Reusa las clases `Parser._pdf_to_markdown`, `Extractor._invoke_model`,
`Loader._ensure_table` directamente. La extracción llama a Vertex AI real
(coste ~$0.001 por CV) y la inserción va a BigQuery real.

## Git workflow para el equipo

**Recomendación: mono-repo** — un solo `cv-pipeline/` compartido por todo el
equipo, como hace el codelab de Google con `eventarc-samples`. Razones:

- El alumno clona, configura su `.env` con `USER_SUFFIX` propio, y despliega.
  Cada uno tiene su pipeline aislado en el mismo proyecto sin pisar al otro.
- Una sola fuente de verdad para el workflow YAML, los scripts y los prompts.
- Las mejoras (un fix en el parser, un cambio en el prompt) se propagan
  vía PR a todos.

**Branching**:

```
main                         ← versión estable, lo que despliegan los alumnos
├── feature/dni-validator    ← cada mejora en su rama
├── feature/refined-prompt
└── fix/bq-streaming-delay
```

Una persona del equipo merge a `main` cuando el cambio está validado.

**Cuándo NO usar mono-repo**: si cada función tiene un owner distinto que
necesita CI/CD independiente, o si hay equipos enteros dedicados a cada
servicio. No es el caso del curso.

**Setup inicial del repo central** (lo hace el instructor una sola vez):

```sh
cd cv-pipeline
git init
git add .
git commit -m "Bootstrap cv-pipeline"
gh repo create cv-pipeline --public --source=. --push   # o gitlab equivalente
```

**Onboarding de un alumno**:

```sh
git clone <url-del-repo>
cd cv-pipeline
cp .env.example .env
$EDITOR .env                         # rellena PROJECT_ID + USER_SUFFIX propio
bash infra/deploy_all.sh
```

## Cleanup

Cuando termines y no quieras seguir pagando por los recursos:

```sh
bash infra/cleanup.sh
```

Borra el trigger, workflow, 4 funciones, 3 buckets (con contenido), dataset
BigQuery (con tablas) y la SA del trigger. **No** deshabilita APIs ni revoca
los roles IAM de la default Compute SA — déjalos por si hay otros recursos
en el proyecto que los usan.

## Troubleshooting

| Síntoma | Causa | Fix |
|---|---|---|
| `Build failed: missing permission on the build service account` justo después de `init.sh` | Propagación IAM | Espera 60s y reintenta el `deploy.sh` |
| `Bucket name already exists` | `USER_SUFFIX` vacío o duplicado | Cambia tu `USER_SUFFIX` en `.env` |
| `Service account ID does not have a length between 6 and 30` | `USER_SUFFIX` demasiado largo | Acórtalo (máx 16 chars) |
| `Workflow execution stuck on ACTIVE` | Función fallando | `gcloud workflows executions describe <id> --workflow=cv-processing-<sufijo>` para ver el step |
| El extractor devuelve JSON vacío para un CV | PDF escaneado, `pypdf` no hace OCR | Para CVs escaneados usar Document AI o Gemini multimodal directo en el `parser` |
| Coste de Vertex AI más alto del esperado | Markdown muy grande | Limitar caracteres del markdown antes de invocar Gemini, o usar Document AI Layout Parser para chunkear |

## Observaciones honestas del pipeline

- **El `parser` con `pypdf` es básico**. Funciona con PDFs nativos (texto
  seleccionable) pero no con escaneados (no hace OCR) y pierde layout en
  CVs con múltiples columnas o fuentes con `letter-spacing` extremo. Para
  producción seria, sustituir por **Document AI Layout Parser** o pasar el
  PDF directamente a Gemini multimodal.
- **El `extractor` con prompt simple extrae mucho ruido**. En tests vimos
  ~130 skills donde 30-40 eran productos genéricos (Excel, WhatsApp, Google).
  El prompt debe afinarse según el caso de uso (segmentar hard_skills /
  tools / domain_knowledge, filtrar irrelevantes).
- **`--allow-unauthenticated` en las funciones** las deja públicas. Vale
  para POC y para el curso. Para producción: quitar el flag y conceder
  `roles/run.invoker` al SA del workflow.
- **Temperature 0 no garantiza determinismo en LLMs**. En tests sobre el mismo
  CV dos invocaciones devolvieron 130 vs 144 skills. Diseña tests sobre
  invariantes (campos presentes, tipos correctos) no sobre igualdad exacta.
