# Módulo 4: Pipelines Basados en Eventos

## Información de la sesión
- **Sesión:** 2 (segunda parte — se imparte junto con el Módulo 3)
- **Fecha:** Lunes 27 de Abril, 2026, 16:00–18:00
- **Tiempo asignado al Módulo 4:** ~50 minutos (temas 4.1–4.5 en vivo)
- **Audiencia:** Ingenieros y analistas de datos avanzados (equipo de People Analytics)
- **Prerequisitos:** Módulos 1, 2 y 3 completados (datasets `bronze_personio`/`silver_personio`/`gold_people_analytics`, bucket `*-datalake` y topic `hr-events` ya creados)
- **Estructura de la sesión:** Repaso → Tema 3 → Tema 4 → Test de Conceptos → Feedback Individual
- **Notebook práctico:** Módulo 4 notebook — notificaciones GCS→Pub/Sub, pipeline event-driven simulado, idempotencia, retry con backoff, validación con dead letter, logging estructurado

### Temas en vivo (Sesión 2):
| Tema | Contenido | Tiempo |
|------|-----------|--------|
| 4.1 | Arquitecturas event-driven en GCP | 10 min |
| 4.2 | Uso de Eventarc para reaccionar a eventos en Cloud Storage | 10 min |
| 4.3 | Automatización de pipelines de Dataflow | 10 min |
| 4.4 | Procesamiento batch basado en eventos | 10 min |
| 4.5 | Buenas prácticas para pipelines resilientes | 10 min |

---

## Tema 4.1: Arquitecturas event-driven en GCP

### Conceptos clave
- Una arquitectura **event-driven** (orientada a eventos) reacciona automáticamente cuando algo ocurre, en lugar de ejecutar procesos en horarios fijos.
- En GCP, el patrón es: **evento** (archivo nuevo, mensaje, cambio de estado) → **trigger** (Eventarc) → **acción** (Cloud Function, Cloud Run, Workflows).
- En People Analytics: cuando un archivo de Personio o de nómina aterriza en Cloud Storage, el pipeline se ejecuta automáticamente sin intervención manual.

### Detalle técnico

**Componentes de una arquitectura event-driven en GCP:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    PRODUCTORES DE EVENTOS                        │
├──────────────┬──────────────┬──────────────┬────────────────────┤
│ Cloud Storage│   Pub/Sub    │ Cloud Audit  │  Custom (API)      │
│ (archivo     │ (mensaje     │ Logs (cambio │  (webhook externo) │
│  nuevo)      │  publicado)  │  IAM, query) │                    │
└──────┬───────┴──────┬───────┴──────┬───────┴────────┬───────────┘
       │              │              │                │
       ▼              ▼              ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        EVENTARC                                  │
│         (enrutador de eventos — el "cerebro")                    │
│  Filtra por tipo, fuente, atributos. Enruta al destino correcto. │
└──────┬───────────────┬──────────────────┬───────────────────────┘
       │               │                  │
       ▼               ▼                  ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────────┐
│Cloud Function│ │  Cloud Run   │ │ Cloud Workflows  │
│(procesamiento│ │ (contenedor) │ │ (orquestación)   │
│ simple)      │ │              │ │                  │
└──────────────┘ └──────────────┘ └──────────────────┘
```

**Tipos de eventos en GCP relevantes para People Analytics:**

| Fuente del evento | Tipo (CloudEvents) | Ejemplo en PA |
|-------------------|--------------------|---------------|
| Cloud Storage | `google.cloud.storage.object.v1.finalized` | Archivo CSV de nómina depositado |
| Cloud Storage | `google.cloud.storage.object.v1.deleted` | Archivo procesado y eliminado |
| Pub/Sub | `google.cloud.pubsub.topic.v1.messagePublished` | Evento de nueva alta recibido |
| BigQuery | `google.cloud.bigquery.v2.JobCompleted` | Query de transformación completada |
| Cloud Audit Logs | `google.cloud.audit.log.v1.written` | Alguien accedió a datos sensibles |

**Ventajas de event-driven vs cron-based:**

| Aspecto | Cron (programado) | Event-driven |
|---------|-------------------|-------------|
| **Latencia** | Depende del intervalo (1h, 1día) | Inmediata (segundos) |
| **Coste** | Se ejecuta aunque no haya datos nuevos | Solo cuando hay eventos |
| **Resiliencia** | Si falla, esperar al siguiente ciclo | Retry automático con backoff |
| **Complejidad** | Baja (Cloud Scheduler + Function) | Media (Eventarc + Function) |
| **Ideal para** | Procesos batch regulares y predecibles | Reaccionar a cambios impredecibles |

### Aplicación en People Analytics
- **Patrón híbrido recomendado:** batch programado (Cloud Scheduler) para el ETL diario, event-driven para archivos que llegan en horarios impredecibles.
- **Caso típico:** el equipo de nómina sube el fichero de salarios "cuando está listo" (no siempre a la misma hora). Eventarc detecta el archivo en `gs://*-datalake/payroll/raw/` y dispara el procesamiento sin necesidad de revisar manualmente.
- **Caso del cliente:** los archivos `personio_history_v2_anon.csv` y `gross_salary_v2_anon.csv` llegan mensualmente; un pipeline event-driven los procesa en cuanto aparecen.

---

## Tema 4.2: Uso de Eventarc para reaccionar a eventos en Cloud Storage

### Conceptos clave
- **Eventarc** es el servicio de GCP que conecta eventos con destinos de forma declarativa.
- El caso de uso más común en PA: "cuando un archivo nuevo aparece en un bucket de GCS, procesarlo automáticamente".
- Eventarc usa **CloudEvents** (estándar CNCF) como formato común de evento, lo que facilita la portabilidad.
- Dos opciones para llevar eventos de GCS a un consumidor: **Eventarc trigger** (gestionado, requiere desplegar Cloud Function/Run) o **GCS Pub/Sub notifications** (más simple, cualquier subscriber puede leer).

### Detalle técnico

**Crear un trigger de Eventarc con gcloud (dispara una Cloud Run service):**

```bash
# Trigger: cuando aparece un archivo nuevo en gs://*-datalake/personio/raw/
gcloud eventarc triggers create trigger-personio-ingesta \
    --location=europe-southwest1 \
    --destination-run-service=procesar-personio \
    --destination-run-region=europe-southwest1 \
    --event-filters="type=google.cloud.storage.object.v1.finalized" \
    --event-filters="bucket=project-9176af0b-ecb3-4050-859-datalake" \
    --service-account=sa-eventarc@project-9176af0b-ecb3-4050-859.iam.gserviceaccount.com
```

**Crear un trigger directo a Cloud Function (gen2):**

```bash
gcloud functions deploy procesar-payroll \
    --gen2 \
    --runtime=python311 \
    --region=europe-southwest1 \
    --source=. \
    --entry-point=procesar_archivo_payroll \
    --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
    --trigger-event-filters="bucket=project-9176af0b-ecb3-4050-859-datalake" \
    --trigger-event-filters-path-pattern="name=payroll/raw/*" \
    --service-account=sa-cf@project-9176af0b-ecb3-4050-859.iam.gserviceaccount.com
```

**Cloud Function que procesa el evento:**

```python
import functions_framework
from cloudevents.http import CloudEvent
from google.cloud import bigquery, storage
import json, logging, re
import pandas as pd
from io import StringIO

log = logging.getLogger("ingesta_personio")

@functions_framework.cloud_event
def procesar_archivo_personio(cloud_event: CloudEvent):
    """
    Cloud Function disparada por Eventarc cuando un archivo nuevo
    aparece en gs://*-datalake/personio/raw/.

    Flujo: GCS → Eventarc → esta función → BigQuery
    """
    # 1. Extraer información del evento (CloudEvent estándar)
    data = cloud_event.data
    bucket_name = data["bucket"]
    file_name = data["name"]
    file_size = int(data.get("size", 0))

    log.info(f"Nuevo archivo: gs://{bucket_name}/{file_name} ({file_size} bytes)")

    # 2. Filtrar: solo procesar archivos de Personio
    if not file_name.startswith("personio/raw/"):
        log.info(f"Archivo fuera de scope: {file_name}. Ignorado.")
        return
    if not file_name.endswith((".csv", ".json")):
        log.warning(f"Formato no soportado: {file_name}.")
        return

    # 3. Leer el archivo de GCS
    gcs_client = storage.Client()
    blob = gcs_client.bucket(bucket_name).blob(file_name)
    contenido = blob.download_as_text(encoding="utf-8")

    # 4. Parsear según formato
    if file_name.endswith(".csv"):
        df = pd.read_csv(StringIO(contenido))
    else:
        datos = json.loads(contenido)
        df = pd.DataFrame(datos if isinstance(datos, list) else datos.get("data", []))

    log.info(f"Registros leídos: {len(df)}")

    # 5. Extraer fecha del path (formato: /personio/raw/YYYY-MM-DD/...)
    fecha_match = re.search(r"(\d{4}-\d{2}-\d{2})", file_name)
    fecha = fecha_match.group(1) if fecha_match else pd.Timestamp.now().strftime("%Y-%m-%d")

    # 6. Añadir metadata
    df["fecha_snapshot"] = fecha
    df["source_file"] = file_name
    df["ingested_at"] = pd.Timestamp.now().isoformat()

    # 7. Cargar a BigQuery (idempotente: borrar + insertar por fecha + fuente)
    bq_client = bigquery.Client()
    table_ref = "project-9176af0b-ecb3-4050-859.bronze_personio.raw_employee_data"

    delete_sql = f"""
    DELETE FROM `{table_ref}`
    WHERE fecha_snapshot = '{fecha}' AND source_file = '{file_name}'
    """
    bq_client.query(delete_sql).result()

    job_config = bigquery.LoadJobConfig(write_disposition="WRITE_APPEND")
    bq_client.load_table_from_dataframe(df, table_ref, job_config=job_config).result()

    log.info(f"Cargadas {len(df)} filas a {table_ref} para fecha {fecha}")
```

**Alternativa más simple — GCS Pub/Sub notifications (lo que se practica en el notebook):**

```bash
# Configurar el bucket para publicar eventos en un topic de Pub/Sub
gcloud storage buckets notifications create gs://project-9176af0b-ecb3-4050-859-datalake \
    --topic=gcs-personio-events \
    --event-types=OBJECT_FINALIZE \
    --object-prefix=personio/raw/
```

Cualquier subscriber del topic `gcs-personio-events` recibe automáticamente los eventos. No requiere desplegar Cloud Function — se puede consumir desde un notebook, un Workflow, o un Cloud Run.

### Aplicación en People Analytics

**Pipeline event-driven completo (caso real del cliente):**

```
1. El equipo de nómina sube "gross_salary_2026_05.csv" a gs://*-datalake/payroll/raw/2026-05/
2. GCS emite evento: google.cloud.storage.object.v1.finalized
3. Eventarc enruta el evento a la Cloud Function "procesar-payroll"
4. La función:
   a. Lee el CSV de GCS
   b. Valida formato y campos obligatorios (employee_code, gross_amount, currency)
   c. Transforma (normaliza monedas, parsea fechas)
   d. Carga a BigQuery (bronze_personio.raw_gross_salary)
   e. Mueve archivo a /processed/2026-05/
5. Cloud Monitoring registra la ejecución exitosa
6. Si falla → retry automático (3 intentos) → dead letter si persiste
7. Dataform recoge los nuevos datos en su próxima ejecución (silver/gold)
```

---

## Tema 4.3: Automatización de pipelines de Dataflow

### Conceptos clave
- **Dataflow** es el servicio de procesamiento de datos masivo de GCP, basado en **Apache Beam**.
- Soporta tanto **batch** como **streaming** con el mismo código (modelo unificado).
- En People Analytics se usa para transformaciones complejas que requieren más potencia que una Cloud Function (ej: procesamiento de millones de registros de fichajes, cruces entre fuentes grandes).
- En el caso del cliente (209 empleados), Dataflow es **excesivo** — se menciona como referencia para escalabilidad futura.

### Detalle técnico

**¿Cuándo usar Dataflow vs Cloud Functions?**

| Criterio | Cloud Functions | Dataflow |
|----------|----------------|----------|
| **Volumen** | < 100K registros | > 100K registros |
| **Duración** | < 9 minutos (límite CF gen2) | Sin límite |
| **Paralelismo** | Limitado | Auto-scaling de workers |
| **Estado** | Stateless | Stateful (windowing, sessions) |
| **Coste mínimo** | ~$0 (pay per invocation) | ~$10-50/mes (workers mínimos) |
| **Complejidad** | Baja | Media-alta (Apache Beam) |
| **Caso PA** | Ingesta diaria de Personio | Procesamiento masivo de fichajes / NLP sobre evaluaciones |

**Pipeline Dataflow batch para People Analytics:**

```python
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
import json

class LimpiarRegistroEmpleado(beam.DoFn):
    """Limpia y normaliza un registro de empleado de Personio."""

    def process(self, element):
        # Normalizar género (Personio devuelve 'female' / 'Female' / 'FEMALE' inconsistente)
        gender = element.get("gender", "").strip().lower()
        element["gender_normalized"] = {"female": "F", "male": "M"}.get(gender, "U")

        # Normalizar position_band a categorías esperadas
        band = element.get("position_band", "").strip().upper()
        if band not in ["P1", "P2", "P3", "E1", "E2", "M2", "M3"]:
            element["position_band_flag"] = "ANOMALIA"

        # Validar salario
        salario = element.get("gross_amount_eur", 0) or 0
        if salario < 15000 or salario > 300000:
            element["salario_flag"] = "ANOMALIA"

        yield element

class ValidarCalidad(beam.DoFn):
    """Valida reglas de calidad y separa registros válidos de inválidos (multi-output)."""

    VALID = "valid"
    INVALID = "invalid"

    def process(self, element):
        errores = []
        if not element.get("employee_code"):
            errores.append("employee_code vacío")
        if not element.get("hire_date"):
            errores.append("hire_date vacío")

        if errores:
            element["errores_validacion"] = "; ".join(errores)
            yield beam.pvalue.TaggedOutput(self.INVALID, element)
        else:
            yield beam.pvalue.TaggedOutput(self.VALID, element)

# Pipeline batch
options = PipelineOptions(
    runner="DataflowRunner",
    project="project-9176af0b-ecb3-4050-859",
    region="europe-southwest1",
    temp_location="gs://project-9176af0b-ecb3-4050-859-datalake/temp/dataflow",
    staging_location="gs://project-9176af0b-ecb3-4050-859-datalake/staging/dataflow",
)

with beam.Pipeline(options=options) as p:
    raw = (
        p
        | "Leer JSON" >> beam.io.ReadFromText("gs://project-9176af0b-ecb3-4050-859-datalake/personio/raw/2026-04-27/*.json")
        | "Parsear" >> beam.Map(json.loads)
    )

    limpio = raw | "Limpiar" >> beam.ParDo(LimpiarRegistroEmpleado())

    validado = limpio | "Validar" >> beam.ParDo(ValidarCalidad()).with_outputs(
        ValidarCalidad.VALID, ValidarCalidad.INVALID
    )

    # Registros válidos → BigQuery Silver
    validado[ValidarCalidad.VALID] | "Escribir Silver" >> beam.io.WriteToBigQuery(
        table="project-9176af0b-ecb3-4050-859:silver_personio.dim_employee",
        write_disposition=beam.io.BigQueryDisposition.WRITE_TRUNCATE,
    )

    # Registros inválidos → tabla de errores para revisión
    validado[ValidarCalidad.INVALID] | "Escribir Errores" >> beam.io.WriteToBigQuery(
        table="project-9176af0b-ecb3-4050-859:bronze_personio.errores_ingesta",
        write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
    )
```

**Templates de Dataflow (sin código):**

GCP ofrece templates preconstruidos para casos comunes que no requieren escribir Apache Beam:

| Template | Uso |
|----------|-----|
| `Cloud Storage Text to BigQuery` | CSV/JSON en GCS → tabla BQ |
| `Pub/Sub to BigQuery` | Stream de mensajes → tabla BQ |
| `Pub/Sub to Cloud Storage` | Stream → archivos en GCS para archivado |
| `BigQuery to Bigtable` | Export para servir baja latencia |
| `JDBC to BigQuery` | Replicación desde BBDD relacional |

```bash
# Lanzar un job de Dataflow desde template (sin código Beam)
gcloud dataflow jobs run job-personio-2026-04-27 \
    --gcs-location=gs://dataflow-templates-europe-southwest1/latest/GCS_Text_to_BigQuery \
    --region=europe-southwest1 \
    --staging-location=gs://*-datalake/temp \
    --parameters \
inputFilePattern=gs://*-datalake/personio/raw/2026-04-27/*.csv,\
JSONPath=gs://*-datalake/configs/personio_schema.json,\
outputTable=project-9176af0b-ecb3-4050-859:bronze_personio.raw_employee_data,\
bigQueryLoadingTemporaryDirectory=gs://*-datalake/temp/bq
```

### Aplicación en People Analytics
- **Cloud Functions para el 90%** de las ingestas de PA (archivos pequeños, transformaciones simples).
- **Dataflow para:** procesamiento de fichajes masivos, NLP sobre evaluaciones de desempeño, cruce de datos entre múltiples fuentes con joins pesados.
- **Dataflow Templates:** gran opción para reemplazar Cloud Functions sin escribir código Beam.

---

## Tema 4.4: Procesamiento batch basado en eventos

### Conceptos clave
- **Batch event-driven** combina lo mejor de ambos mundos: procesamiento en bloques (eficiente) disparado por eventos (reactivo).
- Patrón: acumular eventos durante un periodo o hasta un umbral → procesar todos juntos → cargar resultado.
- Reduce el coste de Pub/Sub + BigQuery (menos jobs, menos invocaciones) sin sacrificar la latencia "casi tiempo real".

### Detalle técnico

**Patrón: micro-batch event-driven:**

```
Eventos HR ──► Pub/Sub ──► Cloud Function (acumula en GCS)
                                │
                         cada 15 min o cada 100 eventos
                                │
                                ▼
                   Cloud Function (batch) ──► BigQuery
```

**Implementación con Cloud Functions + GCS como buffer:**

```python
import functions_framework
from cloudevents.http import CloudEvent
from google.cloud import storage, bigquery
import json
from datetime import datetime

BATCH_SIZE = 100
BUCKET = "project-9176af0b-ecb3-4050-859-datalake"
BUFFER_PREFIX = "buffer/hr-events/"

@functions_framework.cloud_event
def acumular_evento(cloud_event: CloudEvent):
    """Acumula eventos en GCS. Cuando hay suficientes, dispara procesamiento batch."""

    # 1. Guardar evento individual en GCS (buffer)
    data = cloud_event.data
    timestamp = datetime.utcnow().strftime("%Y%m%d%H%M%S%f")

    gcs_client = storage.Client()
    bucket = gcs_client.bucket(BUCKET)
    blob_path = f"{BUFFER_PREFIX}{timestamp}.json"

    bucket.blob(blob_path).upload_from_string(
        json.dumps(data), content_type="application/json"
    )

    # 2. Contar eventos en buffer
    blobs = list(bucket.list_blobs(prefix=BUFFER_PREFIX))

    if len(blobs) >= BATCH_SIZE:
        procesar_batch(bucket, blobs)

def procesar_batch(bucket, blobs):
    """Procesa todos los eventos acumulados en un solo batch."""
    registros = []

    for blob in blobs:
        registros.append(json.loads(blob.download_as_text()))

    bq_client = bigquery.Client()
    table_ref = "project-9176af0b-ecb3-4050-859.bronze_personio.events_batch"

    job_config = bigquery.LoadJobConfig(write_disposition="WRITE_APPEND")
    bq_client.load_table_from_json(registros, table_ref, job_config=job_config).result()

    # Limpiar buffer
    for blob in blobs:
        blob.delete()
```

**Cuándo usar este patrón en People Analytics:**

| Caso | Por qué micro-batch | Latencia objetivo |
|------|---------------------|-------------------|
| Encuestas de clima | Respuestas durante todo el día | 1 hora |
| Webhooks del ATS | Candidatos aplican esporádicamente | 15 minutos |
| Fichajes | Volumen alto, no requiere ms | 5-15 minutos |
| Cambios en HRIS | Pocos eventos al día | 30 minutos |

### Aplicación en People Analytics
- Ideal para **encuestas de clima**: las respuestas llegan durante toda la campaña, se procesan cada hora.
- **Fichajes:** eventos cada segundo → micro-batch cada 15 minutos → carga a BigQuery en lotes.
- **Webhooks del ATS:** candidatos aplican durante el día → batch nocturno consolida (o cada hora si hay urgencia).

---

## Tema 4.5: Buenas prácticas para pipelines resilientes

### Conceptos clave
- Un pipeline resiliente **no falla silenciosamente:** detecta errores, reintenta automáticamente y alerta cuando algo no funciona.
- La resiliencia se diseña, no se improvisa. Cada decisión de diseño tiene una contrapartida en mantenimiento y coste.
- En People Analytics, un pipeline que falla y nadie se entera = un dashboard de RRHH con datos antiguos = decisiones equivocadas en dirección.

### Detalle técnico

**Los 7 principios de un pipeline resiliente:**

| Principio | Implementación | Herramienta GCP |
|-----------|---------------|-----------------|
| **1. Idempotencia** | DELETE + INSERT por fecha/fuente | BigQuery SQL |
| **2. Retry automático** | Reintentar N veces con backoff exponencial | Eventarc retry policy / decorador en código |
| **3. Dead letter queue** | Mensajes que fallan → topic DLQ para revisión | Pub/Sub dead letter |
| **4. Validación de entrada** | Verificar schema, tipos, nulls antes de procesar | Assertions en código, esquemas Avro |
| **5. Logging estructurado** | JSON logs con contexto (archivo, fecha, registros) | Cloud Logging |
| **6. Alertas** | Notificar si el pipeline no se ejecuta o falla | Cloud Monitoring |
| **7. Circuit breaker** | Detener si la tasa de error supera un umbral | Lógica en código |

**Implementación de retry con backoff exponencial:**

```python
import time, logging
from functools import wraps

log = logging.getLogger("pipeline")

def retry_with_backoff(max_retries=3, base_delay=1, max_delay=60):
    """Decorador que reintenta una función con backoff exponencial."""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(max_retries + 1):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_retries:
                        log.error(f"Fallo definitivo tras {max_retries} intentos: {e}")
                        raise
                    delay = min(base_delay * (2 ** attempt), max_delay)
                    log.warning(f"Intento {attempt + 1} falló: {e}. Reintentando en {delay}s...")
                    time.sleep(delay)
        return wrapper
    return decorator

@retry_with_backoff(max_retries=3, base_delay=2)
def cargar_a_bigquery(df, table_ref):
    """Carga datos a BigQuery con retry automático."""
    bq_client = bigquery.Client()
    job_config = bigquery.LoadJobConfig(write_disposition="WRITE_APPEND")
    job = bq_client.load_table_from_dataframe(df, table_ref, job_config=job_config)
    job.result()  # Espera y propaga excepciones
    return job
```

**Logging estructurado (JSON) para Cloud Logging:**

```python
import json, logging, sys

class StructuredLogHandler(logging.Handler):
    """Handler que emite logs en formato JSON para Cloud Logging."""
    def emit(self, record):
        log_entry = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "pipeline": "ingesta_personio",
        }
        # Cloud Logging extrae automáticamente campos JSON; cualquier 'extra' aparece en jsonPayload
        for k, v in record.__dict__.items():
            if k in ("archivo", "registros", "fecha", "duracion_ms"):
                log_entry[k] = v
        print(json.dumps(log_entry), file=sys.stderr)

logger = logging.getLogger("pipeline")
logger.addHandler(StructuredLogHandler())
logger.setLevel(logging.INFO)

# Uso con contexto
logger.info("Archivo procesado", extra={
    "archivo": "gs://*-datalake/personio/raw/2026-04-27/employees.json",
    "registros": 209,
    "fecha": "2026-04-27",
    "duracion_ms": 4523,
})
```

**Alerta de Cloud Monitoring (cuando el pipeline no se ejecuta):**

```yaml
# Política de alerta: si no hay logs del pipeline en las últimas 2 horas (antes de las 09:00)
displayName: "Pipeline Personio no ejecutado"
conditions:
  - displayName: "Sin logs de ingesta en 2h"
    conditionAbsent:
      filter: 'resource.type="cloud_function" AND jsonPayload.pipeline="ingesta_personio"'
      duration: "7200s"  # 2 horas
      trigger:
        count: 1
notificationChannels:
  - "projects/project-9176af0b-ecb3-4050-859/notificationChannels/EMAIL_PA_ADMINS"
alertStrategy:
  autoClose: "86400s"
```

**Patrón completo de pipeline resiliente para PA:**

```python
@retry_with_backoff(max_retries=3)
def pipeline_personio(fecha: str):
    logger.info("Inicio pipeline", extra={"fecha": fecha})

    # 1. Extraer
    datos = extraer_personio_api(fecha)
    logger.info("Datos extraídos", extra={"registros": len(datos), "fecha": fecha})

    # 2. Validar (split valid/invalid)
    validos, invalidos = validar(datos)

    if len(invalidos) / len(datos) > 0.1:  # > 10% inválidos = circuit breaker
        raise ValueError(f"Tasa de errores alta: {len(invalidos)}/{len(datos)}")

    # 3. Cargar válidos a Bronze
    cargar_a_bigquery(pd.DataFrame(validos), "bronze_personio.raw_employee_data")

    # 4. Inválidos → tabla de errores (para revisión humana)
    if invalidos:
        cargar_a_bigquery(pd.DataFrame(invalidos), "bronze_personio.errores_ingesta")
        logger.warning("Registros inválidos", extra={"registros": len(invalidos), "fecha": fecha})

    logger.info("Fin pipeline OK", extra={"fecha": fecha, "validos": len(validos)})
```

### Aplicación en People Analytics
- **Pipeline crítico:** la ingesta diaria del HRIS debe completarse antes de las 09:00. Si falla, RRHH trabaja con datos desactualizados.
- **Alerta mínima:** notificar por email/Slack si el pipeline no se ejecuta antes de las 08:00.
- **Dead letter:** los registros que fallan se guardan en una tabla de errores. Un analista los revisa semanalmente.
- **Testing:** ejecutar el pipeline con datos sintéticos en `*-dev` antes de desplegarlo a producción (ver Módulo 9 sobre CI/CD).
- **Documentación:** cada Cloud Function debe tener su SLA documentado (¿qué hora límite? ¿quién recibe la alerta? ¿quién revisa los errores?).

---

## Conexión con el notebook práctico

El notebook del Módulo 4 aplica estos conceptos de forma práctica sin necesidad de desplegar Cloud Functions (que requeriría Artifact Registry y > 5 min de espera por deploy):

| Tema de presentación | Sección del notebook |
|---------------------|---------------------|
| 4.1 Event-driven en GCP | §2 Configurar notificación GCS → Pub/Sub |
| 4.2 Eventarc reaccionando a GCS | §3 Subir archivo Personio → consumir el evento desde Python |
| 4.2 Cloud Function que procesa | §4 Pipeline event-driven simulado en Python |
| 4.5 Idempotencia | §4 DELETE + INSERT por `fecha_snapshot` + `source_file` |
| 4.5 Retry con backoff | §5 Decorador `retry_with_backoff` |
| 4.5 Validación + dead letter | §6 Split valid/invalid → tabla `errores_ingesta` |
| 4.5 Logging estructurado | §7 `StructuredLogHandler` para Cloud Logging |
| 4.4 Procesamiento batch event-driven | §4 Patrón de procesamiento por archivo completo |
| — | §8 Limpieza idempotente de notification y datos de prueba |

---

## Recursos adicionales
- [Eventarc Documentation](https://cloud.google.com/eventarc/docs)
- [Cloud Functions (2nd gen) triggers](https://cloud.google.com/functions/docs/calling)
- [Dataflow Documentation](https://cloud.google.com/dataflow/docs)
- [Apache Beam Python SDK](https://beam.apache.org/documentation/sdks/python/)
- [Cloud Monitoring alerting](https://cloud.google.com/monitoring/alerts)
- [Structured logging in Cloud Functions](https://cloud.google.com/functions/docs/monitoring/logging)
- [GCS Pub/Sub notifications](https://cloud.google.com/storage/docs/pubsub-notifications)
- [CloudEvents specification](https://cloudevents.io/)
