# Módulo 3: Ingesta de Datos en GCP

## Información de la sesión
- **Sesión:** 3 (compartida con Módulo 4)
- **Fecha:** Lunes 27 de Abril, 16:00–18:00
- **Duración estimada del módulo:** 50 minutos
- **Prerequisitos:** Módulos 1 y 2 completados

---

## Tema 3.1: Introducción a Pub/Sub como sistema de mensajería de GCP

### Conceptos clave
- **Google Cloud Pub/Sub** es un servicio de mensajería asíncrona que desacopla productores y consumidores de datos.
- Modelo publish/subscribe: un **publisher** envía mensajes a un **topic**, y uno o más **subscribers** los reciben a través de **subscriptions**.
- En People Analytics, Pub/Sub permite recibir eventos de RRHH en tiempo real y orquestar pipelines de ingesta.

### Detalle técnico

**Arquitectura de Pub/Sub:**

```
Publisher(s)                    Pub/Sub                         Subscriber(s)
┌──────────┐                ┌─────────────┐                  ┌──────────────┐
│ HRIS API │──mensaje──────►│   Topic     │──subscription A──►│Cloud Function│
│ (evento) │                │ "hr-events" │                  │ (procesar)   │
└──────────┘                │             │──subscription B──►│  Dataflow    │
┌──────────┐                │             │                  │ (streaming)  │
│Webhook   │──mensaje──────►│             │──subscription C──►│  BigQuery    │
│ATS       │                └─────────────┘                  │ (suscr.BQ)   │
└──────────┘                                                 └──────────────┘
```

**Conceptos fundamentales:**

| Concepto | Descripción | Analogía |
|----------|-------------|----------|
| **Topic** | Canal donde se publican mensajes | Tablón de anuncios |
| **Subscription** | Conexión de un consumidor a un topic | Suscripción al tablón |
| **Message** | Unidad de datos enviada (hasta 10 MB) | Nota en el tablón |
| **Ack (acknowledge)** | Confirmación de recepción | Marcar como leído |
| **Dead letter topic** | Topic para mensajes que fallan repetidamente | Bandeja de errores |

**Modos de entrega:**

| Modo | Mecanismo | Latencia | Mejor para |
|------|-----------|----------|-----------|
| **Pull** | El subscriber pide mensajes activamente | Variable | Procesamiento batch, control de ritmo |
| **Push** | Pub/Sub envía a un endpoint HTTP | Baja (~ms) | Cloud Functions, Cloud Run, webhooks |

**Garantías de entrega:**

| Garantía | Descripción |
|----------|-------------|
| **At-least-once** | Por defecto. El mensaje se entrega al menos una vez (puede haber duplicados) |
| **Exactly-once** | Con `enable_exactly_once_delivery=True`. Sin duplicados pero mayor latencia |

**Crear un topic y subscription con Python:**

```python
from google.cloud import pubsub_v1

PROJECT_ID = "pa-people-analytics-prod"

# --- Crear topic ---
publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(PROJECT_ID, "hr-events")

try:
    topic = publisher.create_topic(request={"name": topic_path})
    print(f"Topic creado: {topic.name}")
except Exception as e:
    print(f"Topic ya existe o error: {e}")

# --- Crear subscription ---
subscriber = pubsub_v1.SubscriberClient()
subscription_path = subscriber.subscription_path(PROJECT_ID, "hr-events-etl")

try:
    subscription = subscriber.create_subscription(
        request={
            "name": subscription_path,
            "topic": topic_path,
            "ack_deadline_seconds": 60,  # Tiempo para procesar antes de reenvío
            "retry_policy": {
                "minimum_backoff": {"seconds": 10},
                "maximum_backoff": {"seconds": 600},
            },
            # Dead letter policy: después de 5 intentos, enviar a DLQ
            "dead_letter_policy": {
                "dead_letter_topic": publisher.topic_path(PROJECT_ID, "hr-events-dlq"),
                "max_delivery_attempts": 5,
            },
        }
    )
    print(f"Subscription creada: {subscription.name}")
except Exception as e:
    print(f"Subscription ya existe o error: {e}")
```

### Aplicación en People Analytics

**Eventos típicos de RRHH que se publican en Pub/Sub:**

| Evento | Fuente | Frecuencia | Acción downstream |
|--------|--------|------------|-------------------|
| Nueva alta de empleado | HRIS (webhook) | Esporádico | Insertar en BQ, notificar a onboarding |
| Baja voluntaria | HRIS (webhook) | Esporádico | Actualizar BQ, trigger modelo rotación |
| Cambio salarial | Nómina (batch) | Mensual | Cargar en BQ, recalcular brecha salarial |
| Respuesta de encuesta | Google Forms (webhook) | Campaña | Agregar a BQ, actualizar score clima |
| Fichaje de entrada/salida | Control de acceso | Tiempo real | Streaming a BQ, detección de anomalías |

**Ejemplo: publicar evento de nueva alta:**

```python
import json
from google.cloud import pubsub_v1
from datetime import datetime

publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(PROJECT_ID, "hr-events")

def publicar_evento_alta(empleado_data: dict):
    """Publica un evento de nueva alta en Pub/Sub."""
    mensaje = {
        "event_type": "NUEVA_ALTA",
        "timestamp": datetime.utcnow().isoformat(),
        "payload": {
            "empleado_id": empleado_data["empleado_id"],
            "departamento": empleado_data["departamento"],
            "nivel": empleado_data["nivel"],
            "ciudad": empleado_data["ciudad"],
            "fecha_alta": empleado_data["fecha_alta"],
        }
    }
    
    # Publicar como bytes JSON
    data = json.dumps(mensaje, ensure_ascii=False).encode("utf-8")
    
    # Atributos para filtrado (los subscribers pueden filtrar por atributos)
    future = publisher.publish(
        topic_path,
        data=data,
        event_type="NUEVA_ALTA",
        departamento=empleado_data["departamento"],
    )
    
    message_id = future.result()
    print(f"Evento publicado: {message_id}")
    return message_id

# Uso
publicar_evento_alta({
    "empleado_id": "EMP-02001",
    "departamento": "Tecnología",
    "nivel": "Mid",
    "ciudad": "Madrid",
    "fecha_alta": "2026-04-27",
})
```

---

## Tema 3.2: Integración con APIs externas y sistemas corporativos

### Conceptos clave
- Los sistemas de RRHH (HRIS, ATS, nómina, LMS) exponen datos a través de **APIs REST**, **exports programados** (SFTP/GCS) o **webhooks**.
- La integración debe ser **robusta** (reintentos, idempotencia), **segura** (credenciales en Secret Manager) y **auditable** (logs estructurados).

### Detalle técnico

**Patrones de integración:**

| Patrón | Mecanismo | Frecuencia | Complejidad | Ejemplo en PA |
|--------|-----------|------------|-------------|---------------|
| **API polling** | Script que llama a la API periódicamente | Programada (diaria/horaria) | Media | Extraer empleados de Workday API cada noche |
| **Webhook** | El sistema externo llama a nuestro endpoint | Evento | Media-alta | ATS notifica nueva contratación |
| **File drop** | El sistema deposita un archivo en GCS/SFTP | Programada | Baja | Export diario de SAP a GCS |
| **CDC (Change Data Capture)** | Captura solo los cambios | Continuo | Alta | Stream de cambios desde base de datos del HRIS |

**Integración con SAP SuccessFactors (API OData):**

```python
import requests
import json
import logging
from google.cloud import secretmanager, storage

log = logging.getLogger("ingesta_sap")

def get_secret(secret_id: str) -> str:
    """Obtiene credenciales de Secret Manager."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

def extraer_empleados_sap(fecha: str) -> list:
    """Extrae datos de empleados de SAP SuccessFactors vía API OData."""
    base_url = get_secret("sap-sf-base-url")
    api_key = get_secret("sap-sf-api-key")
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
    }
    
    # OData query: empleados modificados desde la fecha
    endpoint = f"{base_url}/odata/v2/User"
    params = {
        "$filter": f"lastModifiedDateTime ge datetime'{fecha}T00:00:00'",
        "$select": "userId,department,jobLevel,city,hireDate,salary",
        "$top": 1000,
        "$format": "json",
    }
    
    todos_los_empleados = []
    url = endpoint
    
    while url:
        response = requests.get(url, headers=headers, params=params, timeout=30)
        response.raise_for_status()
        data = response.json()
        
        empleados = data.get("d", {}).get("results", [])
        todos_los_empleados.extend(empleados)
        
        # Paginación OData
        url = data.get("d", {}).get("__next", None)
        params = None  # Los params ya están en __next URL
        
        log.info(f"Página extraída: {len(empleados)} empleados (total: {len(todos_los_empleados)})")
    
    return todos_los_empleados

def guardar_en_gcs(datos: list, fecha: str):
    """Guarda los datos extraídos en Cloud Storage como JSON."""
    client = storage.Client()
    bucket = client.bucket("pa-datalake")
    
    blob_path = f"hris/raw/{fecha}/empleados_sap.json"
    blob = bucket.blob(blob_path)
    
    blob.upload_from_string(
        json.dumps(datos, ensure_ascii=False, indent=2),
        content_type="application/json"
    )
    log.info(f"Guardado: gs://pa-datalake/{blob_path} ({len(datos)} registros)")
```

**Integración con ATS (Greenhouse) vía webhook:**

```python
# Cloud Function que recibe webhooks de Greenhouse
import functions_framework
from flask import Request
import json
import hmac
import hashlib

@functions_framework.http
def webhook_greenhouse(request: Request):
    """Recibe webhooks de Greenhouse (ATS) y publica en Pub/Sub."""
    
    # 1. Verificar firma del webhook (seguridad)
    signature = request.headers.get("Signature")
    secret = get_secret("greenhouse-webhook-secret")
    
    body = request.get_data()
    expected = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    
    if not hmac.compare_digest(signature, expected):
        return "Firma inválida", 401
    
    # 2. Parsear el evento
    event = json.loads(body)
    event_type = event.get("action", "unknown")
    
    # 3. Publicar en Pub/Sub para procesamiento asíncrono
    publisher = pubsub_v1.PublisherClient()
    topic = publisher.topic_path(PROJECT_ID, "ats-events")
    
    publisher.publish(
        topic,
        data=body,
        event_type=event_type,
        source="greenhouse",
    )
    
    return "OK", 200
```

### Aplicación en People Analytics

**Mapa de integraciones típico:**

```
┌─────────────────────────────────────────────────────────┐
│                  SISTEMAS FUENTE                         │
├──────────┬──────────┬──────────┬──────────┬─────────────┤
│SAP SF    │Greenhouse│Nómina    │Google    │Control      │
│(HRIS)    │(ATS)     │(A3/Sage) │Forms     │presencia    │
│          │          │          │(encuestas)│             │
│ API OData│ Webhooks │ SFTP/CSV │ API REST │ API/fichero │
└────┬─────┴────┬─────┴────┬─────┴────┬─────┴──────┬──────┘
     │          │          │          │            │
     ▼          ▼          ▼          ▼            ▼
┌─────────────────────────────────────────────────────────┐
│              GCS Landing Zone (Bronze)                    │
│  /hris/raw/  /ats/raw/  /nomina/raw/  /encuestas/raw/   │
└─────────────────────────────────────────────────────────┘
```

---

## Tema 3.3: Arquitecturas de ingestión en tiempo real

### Conceptos clave
- **Streaming** procesa cada evento inmediatamente al llegar. **Batch** acumula datos y los procesa en bloques.
- En People Analytics, la mayoría de los datos son **batch** (exports diarios del HRIS). El streaming se justifica en casos específicos.
- GCP ofrece un stack completo para ambos: Pub/Sub + Dataflow (streaming) o Cloud Functions + GCS (batch).

### Detalle técnico

**Arquitectura de ingestión en tiempo real:**

```
Evento HR ──► Pub/Sub ──► Dataflow (Apache Beam) ──► BigQuery
                │                                        │
                └──► Cloud Function ──► GCS ──► BigQuery │
                     (alternativa simple)                │
                                                         ▼
                                              Dashboard actualizado
                                              en "casi tiempo real"
```

**Streaming con Dataflow (Apache Beam):**

```python
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
import json

class ParseHREvent(beam.DoFn):
    """Parsea un mensaje de Pub/Sub como evento de RRHH."""
    def process(self, element):
        data = json.loads(element.decode("utf-8"))
        yield {
            "empleado_id": data["payload"]["empleado_id"],
            "event_type": data["event_type"],
            "timestamp": data["timestamp"],
            "departamento": data["payload"].get("departamento"),
            "detalles": json.dumps(data["payload"]),
        }

# Pipeline de streaming
options = PipelineOptions(
    runner="DataflowRunner",
    project=PROJECT_ID,
    region="europe-west1",
    temp_location=f"gs://pa-datalake/temp",
    streaming=True,
)

with beam.Pipeline(options=options) as pipeline:
    (
        pipeline
        | "Leer Pub/Sub" >> beam.io.ReadFromPubSub(
            topic=f"projects/{PROJECT_ID}/topics/hr-events"
        )
        | "Parsear evento" >> beam.ParDo(ParseHREvent())
        | "Escribir a BigQuery" >> beam.io.WriteToBigQuery(
            table=f"{PROJECT_ID}:people_analytics.events_stream",
            schema="empleado_id:STRING,event_type:STRING,timestamp:TIMESTAMP,"
                   "departamento:STRING,detalles:STRING",
            write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
            create_disposition=beam.io.BigQueryDisposition.CREATE_IF_NEEDED,
        )
    )
```

**BigQuery Subscription (alternativa sin código):**

```bash
# Crear una suscripción que escribe directamente a BigQuery
# Sin necesidad de Dataflow ni Cloud Functions
gcloud pubsub subscriptions create hr-events-to-bq \
    --topic=hr-events \
    --bigquery-table=pa-prod:people_analytics.events_pubsub \
    --use-topic-schema \
    --write-metadata
```

**¿Cuándo justificar streaming en People Analytics?**

| Caso de uso | ¿Streaming? | Justificación |
|-------------|-------------|---------------|
| Dashboard de rotación mensual | No | Los datos cambian una vez al mes |
| Detección de fraude en fichajes | Sí | Necesita respuesta inmediata |
| Alerta de baja voluntaria inesperada | Sí | RRHH necesita actuar rápido |
| Carga mensual de nómina | No | Datos batch por naturaleza |
| Encuesta de clima (campaña) | No | Se procesa al cerrar la campaña |
| Onboarding automático (nueva alta) | Sí | Iniciar procesos inmediatamente |

### Aplicación en People Analytics
- **Regla pragmática**: empieza con batch. Añade streaming solo cuando el negocio necesite latencia < 1 hora.
- La mayoría de los equipos de PA funcionan con ETL batch diario y es perfectamente suficiente.
- El streaming real aporta valor en alertas (detección de anomalías en fichajes, bajas inesperadas).

---

## Tema 3.4: Comparación de costes y complejidad entre streaming y batch

### Conceptos clave
- Streaming tiene mayor coste operativo y complejidad que batch.
- La decisión debe basarse en el **valor de negocio de la latencia reducida**, no en la moda tecnológica.

### Detalle técnico

**Comparación detallada:**

| Dimensión | Batch | Streaming |
|-----------|-------|-----------|
| **Latencia** | Horas (ETL diario/semanal) | Segundos a minutos |
| **Complejidad** | Baja (Cloud Functions + GCS + BQ) | Alta (Pub/Sub + Dataflow + BQ) |
| **Coste infraestructura** | $10-50/mes (funciones esporádicas) | $100-500/mes (Dataflow workers 24/7) |
| **Coste Pub/Sub** | ~$0 (pocos mensajes batch) | $40/TB de mensajes |
| **Coste Dataflow** | N/A | ~$0.056/vCPU-hora + $0.003/GB-hora |
| **Mantenimiento** | Bajo (scripts simples) | Alto (monitorización, backpressure, errores) |
| **Tolerancia a fallos** | Reejecutar pipeline | Dead letter queues, checkpointing |
| **Debugging** | Logs simples | Logs distribuidos, métricas de lag |
| **Equipo necesario** | 1 ingeniero de datos | 2-3 ingenieros con experiencia en streaming |

**Coste mensual estimado para un equipo de PA (2.000 empleados):**

| Componente | Batch | Streaming |
|------------|-------|-----------|
| Cloud Functions (triggers) | $5 | $5 |
| Pub/Sub | $0 | $10 |
| Dataflow | $0 | $150-300 (workers mínimos) |
| BigQuery (queries) | $50 | $50 |
| BigQuery (storage) | $10 | $15 |
| Cloud Storage | $5 | $5 |
| Cloud Scheduler | $0.10 | $0.10 |
| **Total mensual** | **~$70** | **~$235-385** |

**Árbol de decisión:**

```
¿El negocio necesita datos actualizados en < 1 hora?
├── NO → BATCH (Cloud Functions + GCS + BigQuery)
│         Coste bajo, mantenimiento bajo, suficiente para el 90% de PA
│
└── SÍ → ¿El volumen justifica Dataflow?
          ├── NO (< 10K eventos/día) → Pub/Sub + Cloud Function → BigQuery
          │                             (mini-batch cada 5-15 minutos)
          │
          └── SÍ (> 10K eventos/día) → Pub/Sub + Dataflow → BigQuery
                                        (streaming real)
```

### Aplicación en People Analytics

**Recomendación para la mayoría de equipos de PA:**

1. **Empezar con batch**: ETL diario con Cloud Functions + Cloud Scheduler
2. **Añadir mini-batch** para casos específicos: webhook → Pub/Sub → Cloud Function cada 15 min
3. **Solo streaming** si hay un caso de negocio claro con ROI demostrable

**Ejemplo de pipeline batch recomendado (90% de los casos):**

```
06:00  Cloud Scheduler dispara Cloud Function
06:01  Cloud Function extrae datos de SAP API → guarda en GCS
06:05  Eventarc detecta nuevo archivo en GCS → dispara otra Cloud Function
06:06  Cloud Function carga datos a BigQuery (bronze_empleados)
07:00  Cloud Scheduler dispara Dataform
07:05  Dataform transforma: bronze → silver → gold
07:10  Dashboard de Looker disponible con datos actualizados
```

---

## Recursos adicionales
- [Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Pub/Sub pricing](https://cloud.google.com/pubsub/pricing)
- [Dataflow Documentation](https://cloud.google.com/dataflow/docs)
- [BigQuery subscriptions for Pub/Sub](https://cloud.google.com/pubsub/docs/bigquery)
- [Cloud Functions triggers](https://cloud.google.com/functions/docs/calling)
