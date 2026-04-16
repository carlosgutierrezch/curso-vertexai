# Módulo 4: Pipelines Basados en Eventos

## Información de la sesión
- **Sesión:** 3 (compartida con Módulo 3)
- **Fecha:** Lunes 27 de Abril, 16:00–18:00
- **Duración estimada del módulo:** 55 minutos
- **Prerequisitos:** Módulos 1, 2 y 3 completados

---

## Tema 4.1: Arquitecturas event-driven en GCP

### Conceptos clave
- Una arquitectura **event-driven** (orientada a eventos) reacciona automáticamente cuando algo ocurre, en lugar de ejecutar procesos en horarios fijos.
- En GCP, el patrón es: **evento** (archivo nuevo, mensaje, cambio) → **trigger** (Eventarc) → **acción** (Cloud Function, Cloud Run, Workflows).
- En People Analytics: cuando un archivo de RRHH aterriza en Cloud Storage, el pipeline se ejecuta automáticamente.

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
│  Filtra eventos por tipo, fuente, atributos                      │
│  Enruta al destino correcto                                      │
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

| Fuente del evento | Tipo | Ejemplo en PA |
|-------------------|------|---------------|
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
| **Ideal para** | Procesos batch regulares | Reaccionar a cambios impredecibles |

### Aplicación en People Analytics
- **Híbrido recomendado**: batch programado para el ETL diario, event-driven para archivos que llegan en horarios impredecibles.
- Ejemplo: el equipo de nómina sube el fichero de salarios "cuando está listo" (no siempre a la misma hora). Eventarc detecta el archivo y dispara el procesamiento.

---

## Tema 4.2: Uso de Eventarc para reaccionar a eventos en Cloud Storage

### Conceptos clave
- **Eventarc** es el servicio de GCP que conecta eventos con destinos de forma declarativa.
- El caso de uso más común en PA: "cuando un archivo nuevo aparece en un bucket de GCS, procesarlo automáticamente".
- Eventarc usa **CloudEvents** (estándar CNCF) como formato de evento.

### Detalle técnico

**Crear un trigger de Eventarc con gcloud:**

```bash
# Trigger: cuando aparece un archivo nuevo en gs://pa-datalake/hris/raw/
gcloud eventarc triggers create trigger-hris-ingesta \
    --location=europe-west1 \
    --destination-run-service=procesar-hris \
    --destination-run-region=europe-west1 \
    --event-filters="type=google.cloud.storage.object.v1.finalized" \
    --event-filters="bucket=pa-datalake" \
    --event-filters-path-pattern="prefix=/hris/raw/" \
    --service-account=sa-eventarc@pa-prod.iam.gserviceaccount.com
```

**Crear un trigger con Python (Terraform-style para reproducibilidad):**

```python
# Alternativa: trigger que dispara Cloud Function (gen2)
gcloud eventarc triggers create trigger-nomina-gcs \
    --location=europe-west1 \
    --destination-function=procesar-nomina \
    --destination-function-region=europe-west1 \
    --event-filters="type=google.cloud.storage.object.v1.finalized" \
    --event-filters="bucket=pa-datalake" \
    --event-filters-path-pattern="prefix=/nomina/raw/" \
    --service-account=sa-eventarc@pa-prod.iam.gserviceaccount.com
```

**Cloud Function que procesa el evento:**

```python
import functions_framework
from cloudevents.http import CloudEvent
from google.cloud import bigquery, storage
import json
import logging
import pandas as pd

log = logging.getLogger("ingesta_hris")

@functions_framework.cloud_event
def procesar_archivo_hris(cloud_event: CloudEvent):
    """
    Cloud Function disparada por Eventarc cuando un archivo nuevo
    aparece en gs://pa-datalake/hris/raw/.
    
    Flujo: GCS → Eventarc → esta función → BigQuery
    """
    # 1. Extraer información del evento
    data = cloud_event.data
    bucket_name = data["bucket"]
    file_name = data["name"]
    file_size = int(data.get("size", 0))
    
    log.info(f"Nuevo archivo detectado: gs://{bucket_name}/{file_name} ({file_size} bytes)")
    
    # 2. Validar que es un archivo esperado
    if not file_name.endswith((".csv", ".json")):
        log.warning(f"Formato no soportado: {file_name}. Ignorando.")
        return
    
    # 3. Leer el archivo de GCS
    gcs_client = storage.Client()
    bucket = gcs_client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    
    contenido = blob.download_as_text(encoding="utf-8")
    
    # 4. Transformar según formato
    if file_name.endswith(".csv"):
        from io import StringIO
        df = pd.read_csv(StringIO(contenido))
    elif file_name.endswith(".json"):
        datos = json.loads(contenido)
        df = pd.DataFrame(datos if isinstance(datos, list) else datos.get("results", []))
    
    log.info(f"Registros leídos: {len(df)}")
    
    # 5. Extraer fecha del path (formato: /hris/raw/2026-04-27/archivo.csv)
    import re
    fecha_match = re.search(r"(\d{4}-\d{2}-\d{2})", file_name)
    fecha = fecha_match.group(1) if fecha_match else pd.Timestamp.now().strftime("%Y-%m-%d")
    
    # 6. Añadir metadata
    df["fecha_snapshot"] = fecha
    df["source_file"] = file_name
    df["ingested_at"] = pd.Timestamp.now().isoformat()
    
    # 7. Cargar a BigQuery (idempotente: borrar + insertar)
    bq_client = bigquery.Client()
    table_ref = "pa-prod.people_analytics.bronze_empleados"
    
    # Borrar datos de esta fecha y fuente (idempotencia)
    delete_sql = f"""
    DELETE FROM `{table_ref}` 
    WHERE fecha_snapshot = '{fecha}' AND source_file = '{file_name}'
    """
    bq_client.query(delete_sql).result()
    
    # Insertar nuevos datos
    job_config = bigquery.LoadJobConfig(write_disposition="WRITE_APPEND")
    bq_client.load_table_from_dataframe(df, table_ref, job_config=job_config).result()
    
    log.info(f"Cargadas {len(df)} filas a {table_ref} para fecha {fecha}")
    
    # 8. Mover archivo a /processed/ (no borrar, para auditoría)
    processed_path = file_name.replace("/raw/", "/processed/")
    bucket.copy_blob(blob, bucket, processed_path)
    log.info(f"Archivo copiado a gs://{bucket_name}/{processed_path}")
```

### Aplicación en People Analytics

**Pipeline event-driven completo:**

```
1. Equipo de nómina sube "salarios_abril.csv" a gs://pa-datalake/nomina/raw/2026-04/
2. GCS emite evento: google.cloud.storage.object.v1.finalized
3. Eventarc enruta el evento a la Cloud Function "procesar-nomina"
4. La función:
   a. Lee el CSV de GCS
   b. Valida formato y campos obligatorios
   c. Transforma (normaliza columnas, parsea fechas)
   d. Carga a BigQuery (bronze_nomina)
   e. Mueve archivo a /processed/
5. Cloud Monitoring registra la ejecución exitosa
6. Si falla → retry automático (3 intentos) → dead letter si persiste
```

---

## Tema 4.3: Automatización de pipelines de Dataflow

### Conceptos clave
- **Dataflow** es el servicio de procesamiento de datos masivo de GCP, basado en **Apache Beam**.
- Soporta tanto **batch** como **streaming** con el mismo código.
- En People Analytics se usa para transformaciones complejas que requieren más potencia que una Cloud Function (ej: procesamiento de millones de registros de fichajes).

### Detalle técnico

**¿Cuándo usar Dataflow vs Cloud Functions?**

| Criterio | Cloud Functions | Dataflow |
|----------|----------------|----------|
| **Volumen** | < 100K registros | > 100K registros |
| **Duración** | < 9 minutos (límite CF gen2) | Sin límite |
| **Paralelismo** | Limitado | Auto-scaling workers |
| **Estado** | Stateless | Stateful (windowing, sessions) |
| **Coste mínimo** | ~$0 (pay per invocation) | ~$10-50/mes (workers mínimos) |
| **Complejidad** | Baja | Media-alta (Apache Beam) |

**Pipeline Dataflow batch para People Analytics:**

```python
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
import json

class LimpiarRegistroEmpleado(beam.DoFn):
    """Limpia y normaliza un registro de empleado."""
    
    def process(self, element):
        # Normalizar departamento
        dept_mapping = {
            "IT": "Tecnología", "Tech": "Tecnología", "Engineering": "Tecnología",
            "Sales": "Ventas", "Comercial": "Ventas",
            "HR": "RRHH", "Human Resources": "RRHH", "Personas": "RRHH",
        }
        element["departamento"] = dept_mapping.get(
            element.get("departamento", ""), 
            element.get("departamento", "Desconocido")
        )
        
        # Validar salario
        salario = element.get("salario_bruto", 0)
        if salario < 15000 or salario > 300000:
            element["salario_bruto_flag"] = "ANOMALIA"
        
        # Normalizar nivel
        element["nivel"] = element.get("nivel", "").strip().title()
        
        yield element

class ValidarCalidad(beam.DoFn):
    """Valida reglas de calidad y separa registros válidos de inválidos."""
    
    VALID = "valid"
    INVALID = "invalid"
    
    def process(self, element):
        errores = []
        
        if not element.get("empleado_id"):
            errores.append("empleado_id vacío")
        if not element.get("departamento"):
            errores.append("departamento vacío")
        
        if errores:
            element["errores_validacion"] = "; ".join(errores)
            yield beam.pvalue.TaggedOutput(self.INVALID, element)
        else:
            yield beam.pvalue.TaggedOutput(self.VALID, element)

# Pipeline batch
options = PipelineOptions(
    runner="DataflowRunner",
    project="pa-prod",
    region="europe-west1",
    temp_location="gs://pa-datalake/temp/dataflow",
    staging_location="gs://pa-datalake/staging/dataflow",
)

with beam.Pipeline(options=options) as p:
    # Leer desde GCS
    raw = (
        p
        | "Leer JSON" >> beam.io.ReadFromText("gs://pa-datalake/hris/raw/2026-04-27/*.json")
        | "Parsear" >> beam.Map(json.loads)
    )
    
    # Limpiar
    limpio = raw | "Limpiar" >> beam.ParDo(LimpiarRegistroEmpleado())
    
    # Validar (con outputs múltiples)
    validado = limpio | "Validar" >> beam.ParDo(ValidarCalidad()).with_outputs(
        ValidarCalidad.VALID, ValidarCalidad.INVALID
    )
    
    # Registros válidos → BigQuery Silver
    validado[ValidarCalidad.VALID] | "Escribir Silver" >> beam.io.WriteToBigQuery(
        table="pa-prod:people_analytics.silver_empleados",
        write_disposition=beam.io.BigQueryDisposition.WRITE_TRUNCATE,
    )
    
    # Registros inválidos → tabla de errores para revisión
    validado[ValidarCalidad.INVALID] | "Escribir Errores" >> beam.io.WriteToBigQuery(
        table="pa-prod:people_analytics.errores_ingesta",
        write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
    )
```

### Aplicación en People Analytics
- **Cloud Functions para el 90%** de las ingestas de PA (archivos pequeños, transformaciones simples).
- **Dataflow para**: procesamiento de fichajes masivos, NLP sobre evaluaciones de desempeño, cruce de datos entre múltiples fuentes.
- **Dataflow Templates**: GCP ofrece templates preconstruidos (GCS→BQ, Pub/Sub→BQ) que no requieren código Apache Beam.

---

## Tema 4.4: Procesamiento batch basado en eventos

### Conceptos clave
- **Batch event-driven** combina lo mejor de ambos mundos: procesamiento en bloques (eficiente) disparado por eventos (reactivo).
- Patrón: acumular eventos durante un periodo → procesar todos juntos → cargar resultado.

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

BATCH_SIZE = 100  # Procesar cuando acumule 100 eventos
BUCKET = "pa-datalake"
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
        # 3. Procesar batch
        procesar_batch(bucket, blobs)

def procesar_batch(bucket, blobs):
    """Procesa todos los eventos acumulados en un solo batch."""
    registros = []
    
    for blob in blobs:
        contenido = blob.download_as_text()
        registros.append(json.loads(contenido))
    
    # Cargar batch a BigQuery
    bq_client = bigquery.Client()
    table_ref = "pa-prod.people_analytics.events_batch"
    
    job_config = bigquery.LoadJobConfig(write_disposition="WRITE_APPEND")
    bq_client.load_table_from_json(registros, table_ref, job_config=job_config).result()
    
    # Limpiar buffer
    for blob in blobs:
        blob.delete()
```

### Aplicación en People Analytics
- Ideal para **encuestas de clima**: las respuestas llegan durante todo el día, se procesan cada hora.
- **Fichajes**: eventos cada segundo → micro-batch cada 15 minutos → carga a BigQuery.
- **Webhooks del ATS**: candidatos aplican durante el día → batch nocturno consolida.

---

## Tema 4.5: Buenas prácticas para pipelines resilientes

### Conceptos clave
- Un pipeline resiliente **no falla silenciosamente**: detecta errores, reintenta automáticamente y alerta cuando algo no funciona.
- La resiliencia se diseña, no se improvisa.

### Detalle técnico

**Los 7 principios de un pipeline resiliente:**

| Principio | Implementación | Herramienta GCP |
|-----------|---------------|-----------------|
| **1. Idempotencia** | DELETE + INSERT por fecha/fuente | BigQuery SQL |
| **2. Retry automático** | Reintentar N veces con backoff exponencial | Eventarc retry policy |
| **3. Dead letter queue** | Mensajes que fallan → topic DLQ para revisión | Pub/Sub dead letter |
| **4. Validación de entrada** | Verificar schema, tipos, nulls antes de procesar | Assertions en código |
| **5. Logging estructurado** | JSON logs con contexto (archivo, fecha, registros) | Cloud Logging |
| **6. Alertas** | Notificar si el pipeline no se ejecuta o falla | Cloud Monitoring |
| **7. Circuit breaker** | Detener si la tasa de error supera un umbral | Lógica en código |

**Implementación de retry con backoff exponencial:**

```python
import time
import logging
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
                        log.error(f"Fallo definitivo después de {max_retries} intentos: {e}")
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
    job.result()  # Esperar y propagar excepciones
    return job
```

**Logging estructurado (JSON) para Cloud Logging:**

```python
import json
import logging
import sys

class StructuredLogHandler(logging.Handler):
    """Handler que emite logs en formato JSON para Cloud Logging."""
    def emit(self, record):
        log_entry = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "pipeline": "ingesta_hris",
            "timestamp": self.format(record),
        }
        # Añadir contexto extra si existe
        if hasattr(record, "archivo"):
            log_entry["archivo"] = record.archivo
        if hasattr(record, "registros"):
            log_entry["registros"] = record.registros
            
        print(json.dumps(log_entry), file=sys.stderr)

# Configurar
logger = logging.getLogger("pipeline")
logger.addHandler(StructuredLogHandler())
logger.setLevel(logging.INFO)

# Uso con contexto
logger.info("Archivo procesado", extra={
    "archivo": "gs://pa-datalake/hris/raw/2026-04-27/empleados.json",
    "registros": 2000,
})
```

**Alerta de Cloud Monitoring (cuando el pipeline no se ejecuta):**

```yaml
# Política de alerta: si no hay logs del pipeline en las últimas 2 horas
# Crear vía consola o API de Cloud Monitoring
displayName: "Pipeline HRIS no ejecutado"
conditions:
  - displayName: "Sin logs de ingesta en 2h"
    conditionAbsent:
      filter: 'resource.type="cloud_function" AND jsonPayload.pipeline="ingesta_hris"'
      duration: "7200s"  # 2 horas
      trigger:
        count: 1
notificationChannels:
  - "projects/pa-prod/notificationChannels/EMAIL_CHANNEL_ID"
alertStrategy:
  autoClose: "86400s"  # Auto-cerrar después de 24h
```

### Aplicación en People Analytics
- **Pipeline crítico**: la ingesta diaria del HRIS debe completarse antes de las 09:00. Si falla, RRHH trabaja con datos desactualizados.
- **Alerta mínima**: notificar por email/Slack si el pipeline no se ejecuta antes de las 08:00.
- **Dead letter**: los registros que fallan se guardan en una tabla de errores. Un analista los revisa semanalmente.
- **Testing**: ejecutar el pipeline con datos sintéticos en dev antes de desplegarlo en prod.

---

## Recursos adicionales
- [Eventarc Documentation](https://cloud.google.com/eventarc/docs)
- [Cloud Functions (2nd gen) triggers](https://cloud.google.com/functions/docs/calling)
- [Dataflow Documentation](https://cloud.google.com/dataflow/docs)
- [Apache Beam Python SDK](https://beam.apache.org/documentation/sdks/python/)
- [Cloud Monitoring alerting](https://cloud.google.com/monitoring/alerts)
- [Structured logging in Cloud Functions](https://cloud.google.com/functions/docs/monitoring/logging)
