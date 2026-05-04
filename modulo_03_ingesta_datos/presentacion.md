# Módulo 3: Ingesta de Datos en GCP

## Información de la sesión
- **Sesión:** 2 (primera parte — se imparte junto con el Módulo 4)
- **Fecha:** Lunes 27 de Abril, 2026, 16:00–18:00
- **Tiempo asignado al Módulo 3:** ~45 minutos (temas 3.1–3.4 en vivo)
- **Audiencia:** Ingenieros y analistas de datos avanzados (equipo de People Analytics)
- **Prerequisitos:** Módulos 1 y 2 completados (datasets `bronze_personio`, `silver_personio`, `gold_people_analytics` y bucket `*-datalake` ya creados)
- **Estructura de la sesión:** Repaso → Tema 3 → Tema 4 → Test de Conceptos → Feedback Individual
- **Notebook práctico:** Módulo 3 notebook — Pub/Sub topics y subscriptions, publicación de eventos HR derivados de Personio, BigQuery subscription, comparación batch vs streaming

### Temas en vivo (Sesión 2):
| Tema | Contenido | Tiempo |
|------|-----------|--------|
| 3.1 | Introducción a Pub/Sub como sistema de mensajería de GCP | 15 min |
| 3.2 | Integración con APIs externas y sistemas corporativos | 10 min |
| 3.3 | Arquitecturas de ingestión en tiempo real | 10 min |
| 3.4 | Comparación de costes y complejidad entre streaming y batch | 10 min |

---

## Tema 3.1: Introducción a Pub/Sub como sistema de mensajería de GCP

### Conceptos clave
- **Google Cloud Pub/Sub** es un servicio de mensajería asíncrona que desacopla productores y consumidores de datos.
- Modelo publish/subscribe: un **publisher** envía mensajes a un **topic**, y uno o más **subscribers** los reciben a través de **subscriptions**.
- En People Analytics, Pub/Sub permite recibir eventos de RRHH (alta, baja, cambio salarial, fichaje) de forma asíncrona y orquestar pipelines de ingesta sin acoplar el sistema fuente al consumidor.

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
| **Schema** | Validación de estructura del mensaje (Avro/Protobuf) | Plantilla del formulario |

**Modos de entrega:**

| Modo | Mecanismo | Latencia | Mejor para |
|------|-----------|----------|-----------|
| **Pull** | El subscriber pide mensajes activamente | Variable | Procesamiento batch, control de ritmo, notebooks |
| **Push** | Pub/Sub envía a un endpoint HTTP | Baja (~ms) | Cloud Functions, Cloud Run, webhooks |
| **BigQuery Subscription** | Pub/Sub escribe directo a una tabla BQ | Segundos | Ingesta sin código de eventos a BigQuery |

**Garantías de entrega:**

| Garantía | Descripción | Cuándo usar en PA |
|----------|-------------|-------------------|
| **At-least-once** | Por defecto. El mensaje se entrega al menos una vez (puede haber duplicados) | Eventos donde un duplicado no rompe nada (logs, métricas) |
| **Exactly-once** | Con `enable_exactly_once_delivery=True`. Sin duplicados pero mayor latencia | Cambios salariales, altas y bajas (no se puede duplicar) |

**Crear un topic y subscription con Python:**

```python
from google.cloud import pubsub_v1

PROJECT_ID = "project-9176af0b-ecb3-4050-859"

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

subscription = subscriber.create_subscription(
    request={
        "name": subscription_path,
        "topic": topic_path,
        "ack_deadline_seconds": 60,        # Tiempo para procesar antes de reenvío
        "enable_exactly_once_delivery": True,
        "retry_policy": {
            "minimum_backoff": {"seconds": 10},
            "maximum_backoff": {"seconds": 600},
        },
        # Dead letter policy: tras 5 intentos, enviar a DLQ
        "dead_letter_policy": {
            "dead_letter_topic": publisher.topic_path(PROJECT_ID, "hr-events-dlq"),
            "max_delivery_attempts": 5,
        },
    }
)
print(f"Subscription creada: {subscription.name}")
```

### Aplicación en People Analytics

**Eventos típicos de RRHH que se publican en Pub/Sub:**

| Evento | Fuente | Frecuencia | Acción downstream |
|--------|--------|------------|-------------------|
| Nueva alta de empleado | HRIS Personio (webhook) | Esporádico | Insertar en `bronze_personio`, notificar a onboarding |
| Baja voluntaria | HRIS Personio (webhook) | Esporádico | Actualizar `dim_employee`, trigger modelo de rotación |
| Cambio salarial | Nómina (batch mensual) | Mensual | Cargar en `fact_salary_history`, recalcular brecha salarial |
| Respuesta de encuesta | Google Forms (webhook) | Campaña | Agregar a `gold_people_analytics`, actualizar score de clima |
| Fichaje de entrada/salida | Control de presencia | Tiempo real | Streaming a BigQuery, detección de anomalías |

**Ejemplo: publicar evento de nueva alta usando datos del modelo Personio:**

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
            "employee_code": empleado_data["employee_code"],   # ID Personio
            "department": empleado_data["department"],
            "position_band": empleado_data["position_band"],   # P1-P3, E1-E2, M2-M3
            "office": empleado_data["office"],
            "country": empleado_data["country"],
            "hire_date": empleado_data["hire_date"],
        }
    }

    data = json.dumps(mensaje, ensure_ascii=False).encode("utf-8")

    # Atributos para filtrado (los subscribers pueden filtrar por atributos sin parsear el body)
    future = publisher.publish(
        topic_path,
        data=data,
        event_type="NUEVA_ALTA",
        country=empleado_data["country"],
        department=empleado_data["department"],
    )

    message_id = future.result()
    print(f"Evento publicado: {message_id}")
    return message_id

# Uso con datos compatibles con el esquema Personio
publicar_evento_alta({
    "employee_code": "EMP-02101",
    "department": "Engineering",
    "position_band": "P2",
    "office": "Madrid",
    "country": "ES",
    "hire_date": "2026-04-27",
})
```

---

## Tema 3.2: Integración con APIs externas y sistemas corporativos

### Conceptos clave
- Los sistemas de RRHH (Personio, SAP SF, Workday, ATS, nómina, LMS) exponen datos a través de **APIs REST**, **exports programados** (SFTP/GCS) o **webhooks**.
- La integración debe ser **robusta** (reintentos, idempotencia), **segura** (credenciales en Secret Manager) y **auditable** (logs estructurados).
- En el caso del cliente: la integración real con Personio se hace mediante **export diario a GCS** + procesamiento batch (no streaming). Es el patrón más común en PA.

### Detalle técnico

**Patrones de integración:**

| Patrón | Mecanismo | Frecuencia | Complejidad | Ejemplo en PA |
|--------|-----------|------------|-------------|---------------|
| **API polling** | Script que llama a la API periódicamente | Programada (diaria/horaria) | Media | Extraer empleados de Personio API cada noche |
| **Webhook** | El sistema externo llama a nuestro endpoint | Evento | Media-alta | ATS notifica nueva contratación |
| **File drop** | El sistema deposita un archivo en GCS/SFTP | Programada | Baja | Export diario de Personio a `gs://*-datalake/personio/raw/` |
| **CDC (Change Data Capture)** | Captura solo los cambios | Continuo | Alta | Stream de cambios desde la BBDD del HRIS (raro en PA) |

**Integración con Personio (API REST):**

```python
import requests
import json
import logging
from google.cloud import secretmanager, storage

log = logging.getLogger("ingesta_personio")

def get_secret(secret_id: str, project_id: str) -> str:
    """Obtiene credenciales de Secret Manager (nunca hardcodear)."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

def autenticar_personio(project_id: str) -> str:
    """Obtiene un token de Personio (válido 24 h)."""
    client_id = get_secret("personio-client-id", project_id)
    client_secret = get_secret("personio-client-secret", project_id)

    response = requests.post(
        "https://api.personio.de/v1/auth",
        json={"client_id": client_id, "client_secret": client_secret},
        timeout=30,
    )
    response.raise_for_status()
    return response.json()["data"]["token"]

def extraer_empleados_personio(project_id: str) -> list:
    """Extrae todos los empleados de Personio."""
    token = autenticar_personio(project_id)
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}

    todos = []
    offset = 0
    limit = 200  # Máximo permitido por Personio

    while True:
        response = requests.get(
            "https://api.personio.de/v1/company/employees",
            headers=headers,
            params={"limit": limit, "offset": offset},
            timeout=30,
        )
        response.raise_for_status()
        page = response.json().get("data", [])
        if not page:
            break
        todos.extend(page)
        log.info(f"Página extraída: {len(page)} empleados (total: {len(todos)})")
        offset += limit

    return todos

def guardar_en_gcs(datos: list, bucket: str, fecha: str):
    """Guarda los datos extraídos en Cloud Storage como JSON (capa Bronze)."""
    client = storage.Client()
    blob_path = f"personio/raw/{fecha}/employees.json"
    client.bucket(bucket).blob(blob_path).upload_from_string(
        json.dumps(datos, ensure_ascii=False, indent=2),
        content_type="application/json"
    )
    log.info(f"Guardado: gs://{bucket}/{blob_path} ({len(datos)} registros)")
```

**Integración con ATS (Greenhouse) vía webhook:**

```python
# Cloud Function (gen2) que recibe webhooks y los republica en Pub/Sub
import functions_framework
from flask import Request
from google.cloud import pubsub_v1
import hmac, hashlib, json

@functions_framework.http
def webhook_greenhouse(request: Request):
    """Recibe webhooks de Greenhouse (ATS) y publica en Pub/Sub."""

    # 1. Verificar firma del webhook (seguridad)
    signature = request.headers.get("Signature")
    secret = get_secret("greenhouse-webhook-secret", PROJECT_ID)

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

**Mapa de integraciones típico para el caso del cliente:**

```
┌─────────────────────────────────────────────────────────┐
│                  SISTEMAS FUENTE                         │
├──────────┬──────────┬──────────┬──────────┬─────────────┤
│Personio  │Greenhouse│Nómina    │Google    │Control      │
│(HRIS)    │(ATS)     │(payroll) │Forms     │presencia    │
│          │          │          │(encuestas)│             │
│ API REST │ Webhooks │ SFTP/CSV │ API REST │ API/fichero │
└────┬─────┴────┬─────┴────┬─────┴────┬─────┴──────┬──────┘
     │          │          │          │            │
     ▼          ▼          ▼          ▼            ▼
┌─────────────────────────────────────────────────────────┐
│              GCS Landing Zone (Bronze)                   │
│  /personio/raw/  /ats/raw/  /payroll/raw/  /surveys/    │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
                 BigQuery `bronze_personio`
                           │
                           ▼
              Dataform → silver_personio → gold_people_analytics
```

**Reglas de oro:**
- El **HRIS es la fuente de verdad** para datos maestros del empleado (`dim_employee` se construye desde Personio).
- El **payroll cruza por `employee_code`** — el join key crítico de toda la arquitectura.
- Las **credenciales nunca van en código ni en `.env` de producción**: siempre en Secret Manager.
- Cada fuente debe documentar: frecuencia de actualización, responsable, SLA de calidad.

---

## Tema 3.3: Arquitecturas de ingestión en tiempo real

### Conceptos clave
- **Streaming** procesa cada evento inmediatamente al llegar. **Batch** acumula datos y los procesa en bloques.
- En People Analytics, la mayoría de los datos son **batch** (exports diarios/mensuales). El streaming se justifica solo en casos específicos.
- GCP ofrece un stack completo para ambos: Pub/Sub + Dataflow (streaming real) o Cloud Functions + GCS (batch). Pub/Sub también ofrece **BigQuery Subscriptions** que escriben directo a BQ sin código intermedio.

### Detalle técnico

**Arquitectura de ingestión en tiempo real:**

```
Evento HR ──► Pub/Sub ──► Dataflow (Apache Beam) ──► BigQuery
                │                                        │
                ├──► Cloud Function ──► BigQuery         │
                │    (alternativa simple, < 9 min)       │
                │                                        │
                └──► BigQuery Subscription ─────────────►│
                     (sin código, gestionado)            ▼
                                              Dashboard "casi tiempo real"
```

**Las 3 opciones para streaming a BigQuery, comparadas:**

| Opción | Setup | Coste mínimo | Latencia | Caso ideal en PA |
|--------|-------|-------------|----------|------------------|
| **BigQuery Subscription** | 1 comando gcloud | ~$0 (paga el publisher) | < 10 s | Eventos simples, sin transformación |
| **Cloud Function (push)** | Deploy de función | ~$0 (paga por invocación) | < 30 s | Transformación ligera por mensaje |
| **Dataflow (Beam)** | Pipeline Beam + workers | $150-300/mes (workers 24/7) | < 5 s | Volumen alto + ventanas/agregaciones |

**BigQuery Subscription (la opción más simple — 0 código):**

```bash
# 1. Crear la tabla BQ con el esquema esperado
bq mk --table \
  project-9176af0b-ecb3-4050-859:bronze_personio.events_pubsub \
  event_type:STRING,timestamp:TIMESTAMP,payload:JSON,subscription_name:STRING,message_id:STRING,publish_time:TIMESTAMP

# 2. Crear la subscription que escribe directo a esa tabla
gcloud pubsub subscriptions create hr-events-to-bq \
  --topic=hr-events \
  --bigquery-table=project-9176af0b-ecb3-4050-859:bronze_personio.events_pubsub \
  --write-metadata
```

Cada mensaje publicado en `hr-events` aparece en la tabla en segundos.

**Streaming con Dataflow (cuando el volumen lo justifica):**

```python
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
import json

class ParseHREvent(beam.DoFn):
    """Parsea un mensaje de Pub/Sub como evento de RRHH."""
    def process(self, element):
        data = json.loads(element.decode("utf-8"))
        yield {
            "employee_code": data["payload"]["employee_code"],
            "event_type": data["event_type"],
            "timestamp": data["timestamp"],
            "department": data["payload"].get("department"),
            "country": data["payload"].get("country"),
        }

options = PipelineOptions(
    runner="DataflowRunner",
    project=PROJECT_ID,
    region="europe-southwest1",
    temp_location=f"gs://{BUCKET}/temp",
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
            table=f"{PROJECT_ID}:bronze_personio.events_stream",
            schema="employee_code:STRING,event_type:STRING,timestamp:TIMESTAMP,"
                   "department:STRING,country:STRING",
            write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
            create_disposition=beam.io.BigQueryDisposition.CREATE_IF_NEEDED,
        )
    )
```

**¿Cuándo justificar streaming en People Analytics?**

| Caso de uso | ¿Streaming? | Justificación |
|-------------|-------------|---------------|
| Dashboard de rotación mensual | No | Los datos cambian una vez al mes |
| Detección de fraude en fichajes | Sí | Necesita respuesta inmediata |
| Alerta de baja voluntaria inesperada | Sí | RRHH necesita actuar en el día |
| Carga mensual de nómina | No | Datos batch por naturaleza |
| Encuesta de clima (campaña) | No | Se procesa al cerrar la campaña |
| Onboarding automático (nueva alta) | Sí | Iniciar provisionamiento inmediato |
| Dashboards ejecutivos | No | Refresh diario es suficiente |

### Aplicación en People Analytics
- **Regla pragmática:** empieza con batch. Añade streaming solo cuando el negocio necesite latencia < 1 hora con un caso de uso claro.
- La mayoría de los equipos de PA funcionan con ETL batch diario y es perfectamente suficiente.
- El streaming real aporta valor en alertas (detección de anomalías en fichajes, bajas inesperadas, accesos no autorizados).
- **Para el cliente:** los datos de Personio (209 empleados) son demasiado pequeños para justificar streaming. La práctica del notebook usa Pub/Sub para entender los conceptos, no porque la arquitectura productiva lo requiera.

---

## Tema 3.4: Comparación de costes y complejidad entre streaming y batch

### Conceptos clave
- Streaming tiene mayor coste operativo y complejidad que batch.
- La decisión debe basarse en el **valor de negocio de la latencia reducida**, no en la moda tecnológica.
- En People Analytics, el coste de oportunidad de operar streaming sin necesidad real es alto: el equipo que mantiene el pipeline no atiende otras prioridades.

### Detalle técnico

**Comparación detallada:**

| Dimensión | Batch | Streaming |
|-----------|-------|-----------|
| **Latencia** | Horas (ETL diario/semanal) | Segundos a minutos |
| **Complejidad** | Baja (Cloud Functions + GCS + BQ) | Alta (Pub/Sub + Dataflow + BQ) |
| **Coste infraestructura** | $10-50/mes (funciones esporádicas) | $100-500/mes (Dataflow workers 24/7) |
| **Coste Pub/Sub** | ~$0 (pocos mensajes batch) | $40/TiB de mensajes |
| **Coste Dataflow** | N/A | ~$0.056/vCPU-hora + $0.003/GB-hora |
| **Mantenimiento** | Bajo (scripts simples) | Alto (monitorización, backpressure, errores) |
| **Tolerancia a fallos** | Reejecutar pipeline | Dead letter queues, checkpointing |
| **Debugging** | Logs simples | Logs distribuidos, métricas de lag |
| **Equipo necesario** | 1 ingeniero de datos | 2-3 ingenieros con experiencia en streaming |

**Coste mensual estimado para un equipo de PA del tamaño del cliente (~200-2.000 empleados):**

| Componente | Batch | Streaming |
|------------|-------|-----------|
| Cloud Functions (triggers) | $5 | $5 |
| Pub/Sub | $0 | $10 |
| Dataflow | $0 | $150-300 (workers mínimos) |
| BigQuery (queries) | $30-50 | $30-50 |
| BigQuery (storage) | $5-10 | $5-15 |
| Cloud Storage | $2-5 | $2-5 |
| Cloud Scheduler | $0.10 | $0.10 |
| **Total mensual** | **~$45-70** | **~$200-385** |

**Árbol de decisión:**

```
¿El negocio necesita datos actualizados en < 1 hora?
├── NO → BATCH (Cloud Functions + GCS + BigQuery)
│         Coste bajo, mantenimiento bajo, suficiente para el 90% de PA
│
└── SÍ → ¿El volumen justifica Dataflow?
          ├── NO (< 10K eventos/día) → Pub/Sub + BigQuery Subscription
          │                             (sin código, sin Dataflow)
          │
          └── SÍ (> 10K eventos/día) → Pub/Sub + Dataflow → BigQuery
                                        (streaming real con ventanas)
```

### Aplicación en People Analytics

**Recomendación para la mayoría de equipos de PA:**

1. **Empezar con batch:** ETL diario con Cloud Functions + Cloud Scheduler.
2. **Añadir mini-batch event-driven** para casos específicos: webhook → Pub/Sub → BigQuery Subscription cada pocos segundos.
3. **Solo Dataflow streaming** si hay un caso de negocio con ROI demostrable (> $300/mes en valor generado).

**Ejemplo de pipeline batch recomendado para el caso del cliente (90% de los casos):**

```
06:00  Cloud Scheduler dispara Cloud Function
06:01  Cloud Function extrae datos de Personio API → guarda en gs://*-datalake/personio/raw/YYYY-MM-DD/
06:05  Eventarc detecta nuevo archivo en GCS → dispara otra Cloud Function (Módulo 4)
06:06  Cloud Function carga datos a BigQuery (bronze_personio.raw_employee_data)
07:00  Cloud Scheduler dispara Dataform
07:05  Dataform transforma: bronze → silver → gold (Módulo 8)
07:10  Dashboard de Looker disponible con datos actualizados
```

---

## Conexión con el notebook práctico

El notebook del Módulo 3 aplica estos conceptos de forma práctica:

| Tema de presentación | Sección del notebook |
|---------------------|---------------------|
| 3.1 Pub/Sub: topics y subscriptions | §2 Crear topic `hr-events` y subscription pull |
| 3.1 Publicar mensajes con atributos | §3 Publicar eventos sintéticos derivados de Personio |
| 3.1 Pull subscription | §4 Consumir mensajes con `subscriber.pull()` |
| 3.1 Schema-aware topics | §5 Topic con esquema Avro para validación |
| 3.3 BigQuery Subscription | §6 Suscripción que escribe directo a `bronze_personio.events_pubsub` |
| 3.3 Streaming vs batch | §7 Comparación de patrones con los datos de Personio |
| 3.4 Coste y complejidad | §7 Auditoría del coste de mensajes vs queries con `INFORMATION_SCHEMA` |
| — | §8 Limpieza idempotente de topics y subscriptions |

---

## Recursos adicionales
- [Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Pub/Sub pricing](https://cloud.google.com/pubsub/pricing)
- [BigQuery subscriptions](https://cloud.google.com/pubsub/docs/bigquery)
- [Dataflow Documentation](https://cloud.google.com/dataflow/docs)
- [Cloud Functions triggers](https://cloud.google.com/functions/docs/calling)
- [Personio API reference](https://developer.personio.de/reference)
- [Exactly-once delivery in Pub/Sub](https://cloud.google.com/pubsub/docs/exactly-once-delivery)
