# Módulo 2: Arquitectura Actual de Datos en Google Cloud Platform

## Información de la sesión
- **Sesión:** 2
- **Fecha:** Lunes 20 de Abril, 16:00–18:00
- **Duración:** 2 horas
- **Audiencia:** Ingenieros y analistas de datos avanzados
- **Prerequisitos:** Módulo 1 completado (contexto de People Analytics)

---

## Tema 2.1: Organización por proyectos en GCP para entornos analíticos

### Conceptos clave
- Un **proyecto de GCP** es la unidad fundamental de organización: agrupa recursos, facturación, permisos y APIs.
- En entornos analíticos de People Analytics, la estructura de proyectos determina el aislamiento de datos, el control de costes y la gobernanza.

### Detalle técnico

**Jerarquía de recursos en GCP:**

```
Organización (empresa.com)
  └── Carpeta: People Analytics
        ├── Proyecto: pa-dev          (desarrollo)
        ├── Proyecto: pa-staging      (pre-producción)
        ├── Proyecto: pa-prod         (producción)
        └── Proyecto: pa-sandbox      (experimentación libre)
```

**Estrategias de organización por proyecto:**

| Estrategia | Descripción | Ventajas | Inconvenientes | Recomendado para |
|------------|-------------|----------|----------------|------------------|
| **Un proyecto único** | Todo en un solo proyecto | Simplicidad | Sin aislamiento, riesgo de costes | Prototipos, PoC |
| **Por entorno** | dev / staging / prod | Aislamiento claro, control de permisos | Duplicación de configuración | Equipos medianos |
| **Por dominio + entorno** | pa-rrhh-prod, pa-finance-prod | Máximo aislamiento, facturación granular | Complejidad administrativa | Organizaciones grandes |
| **Por equipo** | pa-team-analytics, pa-team-engineering | Autonomía por equipo | Riesgo de inconsistencia | Equipos autónomos |

**Configuración inicial de un proyecto:**

```python
# Verificar proyecto actual
gcloud config get-value project

# Crear proyecto (requiere permisos de organización)
gcloud projects create pa-people-analytics-prod \
    --name="People Analytics Producción" \
    --organization=ORGANIZATION_ID \
    --folder=FOLDER_ID

# Vincular cuenta de facturación
gcloud billing projects link pa-people-analytics-prod \
    --billing-account=BILLING_ACCOUNT_ID

# Habilitar APIs necesarias
gcloud services enable \
    bigquery.googleapis.com \
    storage.googleapis.com \
    aiplatform.googleapis.com \
    dataform.googleapis.com \
    cloudfunctions.googleapis.com \
    pubsub.googleapis.com \
    eventarc.googleapis.com \
    workflows.googleapis.com \
    cloudscheduler.googleapis.com \
    logging.googleapis.com \
    monitoring.googleapis.com \
    secretmanager.googleapis.com \
    dlp.googleapis.com \
    --project=pa-people-analytics-prod
```

### Aplicación en People Analytics
- **Datos sensibles de empleados** requieren aislamiento estricto: nunca mezclar datos de RRHH con datos de otros dominios en el mismo proyecto.
- El proyecto de People Analytics debe tener su propia cuenta de facturación para visibilidad de costes.
- Recomendación: al menos **3 proyectos** (dev, staging, prod) desde el inicio.

---

## Tema 2.2: Separación entre entornos: desarrollo, test y producción

### Conceptos clave
- La separación de entornos es un **requisito de gobernanza** en datos de personas, no solo una buena práctica.
- Cada entorno tiene un propósito, datos y permisos diferentes.
- GDPR Art. 25 (*Data Protection by Design*) exige que la protección se integre desde el diseño de la arquitectura.

### Detalle técnico

**Definición de entornos:**

| Entorno | Propósito | Datos | Acceso | Frecuencia de despliegue |
|---------|-----------|-------|--------|--------------------------|
| **Desarrollo (dev)** | Experimentación, nuevos features | Sintéticos o anonimizados | Todos los analistas | Continuo |
| **Staging (test)** | Validación pre-producción | Subconjunto anonimizado de prod | Equipo de datos + QA | Antes de cada release |
| **Producción (prod)** | Datos reales, dashboards, modelos | Datos reales de empleados | Solo service accounts + admins | Controlado, con aprobación |
| **Sandbox** | Exploración libre, PoC | Sintéticos | Cualquiera con acceso | Libre |

**Flujo de promoción de código:**

```
Sandbox → Dev → Staging → Prod
   │        │       │        │
   │        │       │        └── Datos reales, permisos mínimos
   │        │       └── Datos anonimizados, test de integración
   │        └── Datos sintéticos, desarrollo de features
   └── Datos sintéticos, experimentación libre
```

**Implementación en GCP:**

```python
# Estructura de datasets en BigQuery por entorno
# Opción A: Proyectos separados (recomendado para prod)
# pa-dev.people_analytics.empleados
# pa-staging.people_analytics.empleados
# pa-prod.people_analytics.empleados

# Opción B: Datasets separados en mismo proyecto (OK para dev/staging)
# pa-analytics.people_analytics_dev.empleados
# pa-analytics.people_analytics_staging.empleados
# pa-analytics.people_analytics_prod.empleados

# Variables de entorno para abstraer el entorno
import os
ENV = os.environ.get("ENVIRONMENT", "dev")
PROJECT = os.environ.get("GCP_PROJECT_ID", f"pa-{ENV}")
DATASET = os.environ.get("BQ_DATASET", f"people_analytics_{ENV}")
```

**Regla de oro:** Los datos de producción de empleados **nunca** se copian a dev o staging sin anonimización previa. Usar `faker` o técnicas de *differential privacy* para generar datos de prueba.

### Aplicación en People Analytics
- En dev/staging se trabaja con el dataset sintético de 2.000 empleados generado en el Módulo 1.
- En producción, los datos reales de RRHH provienen del HRIS y se cargan mediante pipelines automatizados.
- El acceso a producción se limita a service accounts y a un grupo reducido de administradores.

---

## Tema 2.3: Arquitectura típica en People Analytics

### Conceptos clave
- La arquitectura de datos en People Analytics sigue el patrón **medallion** (Bronze → Silver → Gold) adaptado al contexto de RRHH.
- El stack de GCP proporciona todos los componentes necesarios para una arquitectura analítica completa.

### Detalle técnico

**Arquitectura de referencia:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FUENTES DE DATOS                             │
├──────────┬──────────┬──────────┬──────────┬──────────┬─────────────┤
│SAP SF    │Workday   │Encuestas │Fichajes  │LMS       │APIs externas│
│(HRIS)    │(HRIS)    │(Forms)   │(control) │(formación)│(benchmarks) │
└────┬─────┴────┬─────┴────┬─────┴────┬─────┴────┬─────┴──────┬──────┘
     │          │          │          │          │            │
     ▼          ▼          ▼          ▼          ▼            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    CAPA DE INGESTA                                   │
│  Cloud Storage (landing zone) + Pub/Sub (eventos en tiempo real)    │
│  Cloud Data Fusion / Dataflow (ETL) + Cloud Functions (triggers)    │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    CAPA DE ALMACENAMIENTO                           │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │   BRONZE     │  │   SILVER     │  │    GOLD      │              │
│  │  (raw data)  │→ │  (clean)     │→ │  (business)  │              │
│  │  Cloud       │  │  BigQuery    │  │  BigQuery    │              │
│  │  Storage     │  │  Dataform    │  │  Vistas/     │              │
│  │              │  │              │  │  Materializadas│             │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
│                                                                     │
│  BigQuery (Data Warehouse) + Cloud Storage (Data Lake)              │
│  BigLake (unificación) + Analytics Hub (compartición)               │
└────────────┬──────────────────┬──────────────────┬──────────────────┘
             │                  │                  │
             ▼                  ▼                  ▼
┌────────────────┐  ┌────────────────┐  ┌─────────────────────┐
│  CONSUMO       │  │  ML / AI       │  │  GOBERNANZA         │
│                │  │                │  │                     │
│  Looker Studio │  │  Vertex AI     │  │  IAM                │
│  Looker        │  │  BigQuery ML   │  │  Cloud DLP          │
│  Connected     │  │  Gemini        │  │  Cloud Audit Logs   │
│  Sheets        │  │  AutoML        │  │  Secret Manager     │
│                │  │  Workbench     │  │  Data Catalog       │
└────────────────┘  └────────────────┘  └─────────────────────┘
```

**Componentes clave y su rol:**

| Componente | Servicio GCP | Rol en People Analytics |
|------------|-------------|------------------------|
| Data Lake | Cloud Storage | Almacén de datos crudos (CSVs, JSONs, exports) |
| Data Warehouse | BigQuery | Almacén analítico, consultas SQL, ML |
| Transformación | Dataform | ELT: transformar datos en BigQuery |
| Ingesta batch | Cloud Functions + GCS | Procesar archivos cuando se depositan |
| Ingesta streaming | Pub/Sub + Dataflow | Eventos en tiempo real (opcional en PA) |
| Orquestación | Cloud Workflows / Composer | Coordinar pipelines de datos |
| ML/AI | Vertex AI + BigQuery ML | Modelos predictivos (rotación, segmentación) |
| IA Generativa | Gemini (Vertex AI) | Insights automáticos, SQL desde lenguaje natural |
| Visualización | Looker / Looker Studio | Dashboards para RRHH y dirección |
| Seguridad | IAM + DLP + Secret Manager | Protección de datos sensibles |
| Monitorización | Cloud Logging + Monitoring | Salud de pipelines y alertas |

### Aplicación en People Analytics
- La mayoría de los datos de RRHH son **batch** (exports diarios/semanales del HRIS), no streaming.
- Excepciones de streaming: alertas de acceso no autorizado, eventos de fichaje en tiempo real.
- El patrón medallion se adapta bien: Bronze = export crudo de SAP, Silver = datos limpios y normalizados, Gold = métricas de negocio (tasa de rotación, brecha salarial, headcount).

---

## Tema 2.4: Integración de fuentes internas (HRIS, nómina, ATS)

### Conceptos clave
- En People Analytics, los datos vienen de múltiples sistemas que **no hablan entre sí**.
- La integración es el mayor reto técnico: diferentes formatos, frecuencias, calidades y esquemas.
- El empleado debe tener un **identificador único** que permita cruzar datos entre sistemas.

### Detalle técnico

**Fuentes típicas y sus características:**

| Sistema | Tipo | Datos | Formato típico | Frecuencia | Reto principal |
|---------|------|-------|----------------|------------|----------------|
| **HRIS** (SAP SF, Workday, Meta4) | Core HR | Datos maestros, estructura org., contratos | API REST / SFTP / CSV | Diaria | Complejidad del esquema, encoding |
| **Nómina** (SAP, A3, Sage) | Compensación | Salarios, variables, deducciones | CSV / fichero plano | Mensual | Formato propietario, sensibilidad |
| **ATS** (Greenhouse, Lever, Workable) | Selección | Candidatos, entrevistas, ofertas | API REST / webhooks | Tiempo real | Volumen variable, PII candidatos |
| **LMS** (Cornerstone, SAP LMS) | Formación | Cursos, completados, horas | API REST / CSV | Semanal | Estandarización de IDs |
| **Encuestas** (Google Forms, Qualtrics) | Clima/engagement | Respuestas, scores | CSV / API | Trimestral | Anonimización, tamaño muestral |
| **Fichajes** (control de presencia) | Asistencia | Entradas, salidas, ausencias | API / fichero plano | Diaria | Volumen alto, calidad variable |
| **Evaluaciones** (plataforma de talent) | Desempeño | Ratings, textos, objetivos | API REST / CSV | Semestral | Texto libre, sesgos |

**Patrón de integración recomendado:**

```python
# Patrón: cada fuente deposita sus datos en una ruta específica de GCS
# El pipeline los recoge, transforma e inserta en BigQuery

# Estructura en Cloud Storage:
# gs://pa-datalake/
#   ├── hris/raw/2026-04-20/empleados.json
#   ├── nomina/raw/2026-04/salarios.csv
#   ├── ats/raw/2026-04-20/candidatos.json
#   ├── encuestas/raw/2026-Q1/clima.csv
#   └── fichajes/raw/2026-04-20/registros.csv

from google.cloud import storage, bigquery

def ingest_hris_daily(date: str):
    """Ingesta diaria del HRIS: lee JSON de GCS, transforma, carga a BQ."""
    gcs_client = storage.Client()
    bq_client = bigquery.Client()
    
    # 1. Leer datos crudos de GCS
    bucket = gcs_client.bucket("pa-datalake")
    blob = bucket.blob(f"hris/raw/{date}/empleados.json")
    raw_data = json.loads(blob.download_as_text())
    
    # 2. Transformar: mapear campos del HRIS a nuestro esquema
    rows = [transform_hris_record(record) for record in raw_data]
    
    # 3. Cargar a BigQuery (idempotente: borrar fecha primero)
    table_ref = f"{PROJECT}.{DATASET}.bronze_empleados"
    bq_client.query(f"DELETE FROM `{table_ref}` WHERE fecha_snapshot = '{date}'").result()
    
    job_config = bigquery.LoadJobConfig(write_disposition="WRITE_APPEND")
    bq_client.load_table_from_json(rows, table_ref, job_config=job_config).result()
```

**Resolución de identidad del empleado:**

| Problema | Solución |
|----------|----------|
| Cada sistema tiene un ID diferente (SAP: PERNR, ATS: candidate_id) | Tabla maestra `dim_empleado` con mapeo de IDs |
| Empleados con nombre diferente entre sistemas | Normalización (quitar acentos, mayúsculas, espacios) |
| Empleados que cambian de sistema (ej: de ATS a HRIS al ser contratados) | Linking table con fecha de transición |

### Aplicación en People Analytics
- El 80% del tiempo de un proyecto de PA se va en integración y limpieza de datos.
- Priorizar la integración del HRIS como fuente maestra (*source of truth*) de datos de empleados.
- Cada fuente debe documentar: frecuencia de actualización, responsable, SLA de calidad.

---

## Tema 2.5: Ingesta segura de datos sensibles

### Conceptos clave
- Los datos de empleados son **datos personales** bajo GDPR y potencialmente **datos de categorías especiales** (Art. 9).
- La ingesta debe garantizar: cifrado en tránsito, cifrado en reposo, trazabilidad y minimización.

### Detalle técnico

**Cadena de custodia del dato:**

```
Fuente (HRIS) → Transferencia cifrada (HTTPS/SFTP) → Landing zone (GCS cifrado) → 
→ Procesamiento (sin almacenar en disco local) → BigQuery (cifrado + permisos)
```

**Medidas de seguridad por capa:**

| Capa | Medida | Implementación en GCP |
|------|--------|----------------------|
| **Transferencia** | TLS 1.2+ / SFTP | APIs de GCP usan HTTPS por defecto |
| **Landing zone** | Cifrado en reposo | GCS: CMEK o Google-managed encryption |
| **Procesamiento** | Sin persistencia local | Cloud Functions: procesamiento en memoria |
| **Almacenamiento** | Cifrado + permisos granulares | BigQuery: CMEK, column-level security |
| **Acceso** | Principio de mínimo privilegio | IAM roles específicos por dataset |
| **Auditoría** | Registro de todos los accesos | Cloud Audit Logs habilitados |

**Ejemplo: ingesta segura con credenciales en Secret Manager:**

```python
from google.cloud import secretmanager

def get_secret(secret_id: str) -> str:
    """Obtiene un secreto de Secret Manager (nunca hardcodear credenciales)."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

# Uso: obtener credenciales del HRIS para la API
hris_api_key = get_secret("hris-api-key")
hris_endpoint = get_secret("hris-endpoint-url")
```

### Aplicación en People Analytics
- **Nunca** almacenar credenciales de APIs en código, archivos `.env` en producción o variables de entorno expuestas. Usar **Secret Manager**.
- Los datos de nómina (salarios) requieren cifrado adicional y acceso restringido incluso dentro del equipo de datos.
- Implementar alertas de Cloud DLP para detectar PII no esperada en la landing zone.

---

## Tema 2.6: Data Lake vs Data Warehouse en GCP

### Conceptos clave

| Concepto | Data Lake (Cloud Storage) | Data Warehouse (BigQuery) |
|----------|--------------------------|--------------------------|
| **Formato** | Cualquiera (CSV, JSON, Parquet, Avro) | Tablas estructuradas con esquema |
| **Esquema** | Schema-on-read | Schema-on-write |
| **Consulta** | Necesita motor externo | SQL nativo, optimizado |
| **Coste almacenamiento** | ~$0.020/GB/mes (Standard) | ~$0.020/GB/mes (activo), $0.010 (long-term) |
| **Coste consulta** | Depende del motor | $6.25/TB procesado (on-demand) |
| **Uso principal** | Almacenamiento raw, archivos grandes | Análisis, reporting, ML |

### Detalle técnico

**¿Cuándo usar cada uno en People Analytics?**

| Caso de uso | Data Lake (GCS) | Data Warehouse (BQ) |
|-------------|----------------|---------------------|
| Recibir exports crudos del HRIS | ✅ | ❌ |
| Almacenar CVs y documentos | ✅ | ❌ |
| Consultas SQL analíticas | ❌ | ✅ |
| Dashboard de rotación | ❌ | ✅ |
| Modelo de ML (training data) | ❌ | ✅ (o GCS para Vertex AI) |
| Backup de datos históricos | ✅ | ❌ (más caro) |
| Archivo de datos > 1 año | ✅ (Coldline/Archive) | ❌ |

**Patrón recomendado — Lakehouse con BigLake:**

```
Cloud Storage (Data Lake)                    BigQuery (Data Warehouse)
┌────────────────────────┐                   ┌────────────────────────┐
│ /raw/hris/2026-04-20/  │                   │ bronze_empleados       │
│ /raw/nomina/2026-04/   │──── Dataform ────►│ silver_empleados       │
│ /raw/encuestas/Q1/     │    (ELT)          │ gold_metricas_rotacion │
│                        │                   │ gold_brecha_salarial   │
│ /processed/parquet/    │◄── Export ────────│                        │
│ /archive/2025/         │                   │                        │
└────────────────────────┘                   └────────────────────────┘
              │                                         │
              └─────────── BigLake ─────────────────────┘
                    (consulta unificada)
```

### Aplicación en People Analytics
- **Estrategia recomendada**: GCS como landing zone y archivo, BigQuery como motor analítico.
- Los datos crudos se mantienen en GCS para auditoría (GDPR Art. 30: registro de actividades de tratamiento).
- BigQuery para todo el análisis: la potencia de SQL + ML integrado justifica centralizar ahí los datos procesados.

---

## Tema 2.7: Flujo extremo a extremo desde origen hasta dashboard

### Conceptos clave
- Un flujo E2E bien diseñado permite que los datos fluyan desde el HRIS hasta un dashboard de Looker **sin intervención manual**.
- La automatización no es un lujo — es un requisito para datos fiables y actualizados.

### Detalle técnico

**Flujo completo para el KPI "Tasa de rotación mensual":**

```
1. ORIGEN
   SAP SuccessFactors → API export → JSON

2. INGESTA (diaria, 06:00h)
   Cloud Scheduler → Cloud Function → descarga API → GCS (/raw/hris/YYYY-MM-DD/)

3. TRIGGER
   Eventarc detecta nuevo archivo en GCS → dispara Cloud Function de procesamiento

4. TRANSFORMACIÓN (Bronze → Silver → Gold)
   Cloud Function → inserta en bronze_empleados (BigQuery)
   Dataform (programado 07:00h) → silver_empleados → gold_metricas_rotacion

5. CONSUMO
   Looker Studio → conecta a gold_metricas_rotacion → dashboard de rotación
   Looker → modelo LookML → métricas oficiales para dirección

6. MONITORIZACIÓN
   Cloud Monitoring → alerta si Dataform falla o si datos no llegan antes de las 08:00h
   Cloud Logging → registro de cada paso para auditoría
```

**Tiempos típicos:**

| Paso | Duración | SLA |
|------|----------|-----|
| Export del HRIS | 5-15 min | < 30 min |
| Transferencia a GCS | 1-5 min | < 10 min |
| Procesamiento Cloud Function | 2-10 min | < 15 min |
| Transformación Dataform | 5-20 min | < 30 min |
| Dashboard disponible | — | Antes de las 09:00h |

### Aplicación en People Analytics
- El dashboard de rotación debe estar actualizado **cada mañana** antes de que RRHH empiece su jornada.
- El SLA del dato (frescura) debe acordarse con RRHH y documentarse.
- Implementar una página de "estado del dato" en Looker que muestre cuándo fue la última actualización.

---

## Tema 2.8: Gestión de identidades y accesos (IAM)

### Conceptos clave
- IAM (*Identity and Access Management*) en GCP controla **quién** puede hacer **qué** sobre **qué recurso**.
- En People Analytics, IAM es crítico: un error de permisos puede exponer salarios, datos de salud o evaluaciones de desempeño.
- Principio fundamental: **mínimo privilegio** — cada persona y service account tiene solo los permisos estrictamente necesarios.

### Detalle técnico

**Modelo de IAM en GCP:**

```
Principal (quién)  →  Rol (qué puede hacer)  →  Recurso (sobre qué)

Ejemplo:
analista@empresa.com → roles/bigquery.dataViewer → dataset:people_analytics_gold
sa-etl@proyecto.iam   → roles/bigquery.dataEditor → dataset:people_analytics_silver
```

**Roles recomendados para People Analytics:**

| Rol | Principal | Acceso |
|-----|-----------|--------|
| `bigquery.dataViewer` | Analistas de RRHH | Solo lectura en Gold |
| `bigquery.dataEditor` | Service account ETL | Lectura/escritura en Bronze/Silver |
| `bigquery.jobUser` | Todos los que ejecutan queries | Ejecutar consultas |
| `storage.objectViewer` | Service account ETL | Leer archivos de GCS |
| `storage.objectCreator` | Service account ingesta | Escribir archivos a GCS |
| `dataform.editor` | Ingenieros de datos | Editar transformaciones |
| `aiplatform.user` | Data scientists | Usar Vertex AI |
| `secretmanager.secretAccessor` | Service accounts | Acceder a credenciales |

**Nunca usar estos roles en producción:**

| Rol peligroso | Por qué | Alternativa |
|---------------|---------|-------------|
| `roles/owner` | Acceso total, sin restricciones | Roles específicos |
| `roles/editor` | Demasiado amplio | Roles por servicio |
| `roles/bigquery.admin` | Puede borrar datasets | `dataEditor` + `jobUser` |

**Buenas prácticas:**

```python
# Asignar permisos a grupos, no a personas individuales
# Grupos recomendados:
# - pa-admins@empresa.com     → roles/owner (solo en emergencias)
# - pa-engineers@empresa.com  → roles/bigquery.dataEditor + dataform.editor
# - pa-analysts@empresa.com   → roles/bigquery.dataViewer (solo Gold)
# - pa-rrhh@empresa.com       → roles/bigquery.dataViewer (solo dashboards)

# Service accounts por función:
# - sa-ingesta@proyecto.iam   → solo GCS write + BQ write en Bronze
# - sa-dataform@proyecto.iam  → BQ read/write en Silver/Gold
# - sa-looker@proyecto.iam    → solo BQ read en Gold
```

### Aplicación en People Analytics
- Los analistas de RRHH solo ven datos Gold (métricas agregadas, dashboards). **Nunca** acceso directo a datos individuales.
- Los ingenieros de datos acceden a Bronze/Silver pero no necesariamente ven el contenido (pueden transformar sin ver salarios).
- Implementar **column-level security** para campos como `salario_bruto`, `genero`, `edad` (se cubre en Módulo 11).

---

## Tema 2.9: Control de costes en arquitecturas analíticas

### Conceptos clave
- BigQuery cobra por **datos procesados** (on-demand) o por **capacidad reservada** (Editions).
- Cloud Storage cobra por **almacenamiento** y **operaciones** (lecturas, escrituras).
- Sin control, un equipo de analistas puede generar facturas sorpresa con queries sobre tablas sin particionar.

### Detalle técnico

**Principales fuentes de coste en People Analytics:**

| Servicio | Modelo de coste | Coste típico en PA | Cómo controlar |
|----------|----------------|--------------------|--------------  |
| BigQuery queries | $6.25/TB procesado | $50-500/mes | Particionado, clustering, LIMIT |
| BigQuery storage | $0.020/GB/mes (activo) | $10-50/mes | Retención, compresión, archive |
| Cloud Storage | $0.020/GB/mes (Standard) | $5-20/mes | Lifecycle policies, clases frías |
| Cloud Functions | $0.40/millón invocaciones | $1-10/mes | Optimizar frecuencia |
| Vertex AI | Variable según uso | $10-100/mes | AutoML budget, endpoints mínimos |

**Herramientas de control:**

```sql
-- Ver coste de las queries más caras del último mes
SELECT
    user_email,
    COUNT(*) AS num_queries,
    ROUND(SUM(total_bytes_processed) / POW(1024, 4), 2) AS tb_procesados,
    ROUND(SUM(total_bytes_processed) / POW(1024, 4) * 6.25, 2) AS coste_estimado_usd
FROM `region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
GROUP BY user_email
ORDER BY coste_estimado_usd DESC
LIMIT 20;
```

**Presupuestos y alertas:**

```bash
# Crear alerta de presupuesto en Cloud Billing
# Consola: Billing → Budgets & alerts → Create Budget
# Configurar alertas al 50%, 80% y 100% del presupuesto mensual
# Enviar notificaciones a pa-admins@empresa.com
```

### Aplicación en People Analytics
- Datasets de PA son relativamente pequeños (miles de empleados, no millones de transacciones), así que los costes son moderados.
- El mayor riesgo de coste: queries exploratórias sin filtro de partición (`SELECT * FROM empleados` sin `WHERE fecha_snapshot = ...`).
- Solución: `require_partition_filter = True` en todas las tablas particionadas (ver Módulo 6).

---

## Tema 2.10: Diseño orientado a escalabilidad y mantenibilidad

### Conceptos clave
- **Escalabilidad**: la arquitectura debe funcionar igual con 500 que con 50.000 empleados.
- **Mantenibilidad**: el código, las transformaciones y los pipelines deben ser fáciles de entender, modificar y depurar.
- La deuda técnica en datos es invisible hasta que causa un error en un informe para dirección.

### Detalle técnico

**Principios de diseño:**

| Principio | Descripción | Ejemplo en PA |
|-----------|-------------|---------------|
| **Idempotencia** | Ejecutar N veces = mismo resultado | DELETE + INSERT por fecha en ETL |
| **Modularidad** | Componentes independientes y reutilizables | Un modelo Dataform por tabla |
| **Documentación** | Cada tabla, campo y pipeline documentado | Descripciones en BigQuery schema |
| **Observabilidad** | Saber qué pasó, cuándo y por qué | Logging estructurado, métricas |
| **Versionado** | Todo el código en Git | Dataform + GitHub |
| **Naming conventions** | Nomenclatura consistente | `bronze_`, `silver_`, `gold_`, `dim_`, `fact_` |

**Nomenclatura recomendada:**

```
Datasets:
  people_analytics_bronze   (datos crudos)
  people_analytics_silver   (datos limpios)
  people_analytics_gold     (métricas de negocio)

Tablas:
  bronze_empleados          (ingesta cruda del HRIS)
  silver_empleados          (limpio, normalizado, tipado)
  gold_rotacion_mensual     (tasa de rotación por departamento)
  dim_empleado              (dimensión: datos maestros del empleado)
  fact_evaluacion           (fact table: evaluaciones de desempeño)

Vistas:
  v_headcount_actual        (headcount a fecha de hoy)
  v_brecha_salarial         (brecha salarial por nivel y género)

Cloud Storage:
  gs://pa-datalake/hris/raw/YYYY-MM-DD/
  gs://pa-datalake/hris/processed/YYYY-MM-DD/
  gs://pa-datalake/encuestas/raw/YYYY-QN/
```

### Aplicación en People Analytics
- Empezar con una arquitectura simple (GCS + BigQuery + Looker) y añadir complejidad solo cuando sea necesario.
- La mantenibilidad importa más que la sofisticación: si el ingeniero de datos se va de vacaciones, ¿puede otro entender los pipelines?
- Documentar las **decisiones de negocio** en el código: ¿por qué se excluyen los becarios del headcount? ¿Qué significa "rotación voluntaria"?

---

## Tema 2.11: BigLake para extender BigQuery a data lakes externos

### Conceptos clave
- **BigLake** permite consultar datos en Cloud Storage directamente desde BigQuery, sin necesidad de cargarlos primero.
- Unifica el acceso a datos del data lake (GCS) y del data warehouse (BigQuery) con una capa de seguridad común.
- Útil cuando los datos son demasiado grandes o demasiado efímeros para cargarlos a BigQuery.

### Detalle técnico

**Arquitectura con BigLake:**

```
Cloud Storage (Parquet/ORC/JSON)
         │
         ▼
    BigLake API ──── Permisos IAM unificados
         │
         ▼
    BigQuery ──── SQL estándar sobre datos en GCS
```

**Crear una tabla BigLake:**

```sql
-- Tabla externa sobre archivos Parquet en GCS
CREATE OR REPLACE EXTERNAL TABLE `people_analytics.ext_fichajes`
WITH CONNECTION `projects/pa-prod/locations/eu/connections/biglake-conn`
OPTIONS (
    format = 'PARQUET',
    uris = ['gs://pa-datalake/fichajes/processed/2026-*.parquet'],
    -- BigLake aplica los mismos permisos IAM que BigQuery
    -- No es necesario dar acceso directo al bucket
);

-- Consultar como cualquier otra tabla de BigQuery
SELECT
    empleado_id,
    DATE(timestamp_entrada) AS fecha,
    COUNT(*) AS fichajes
FROM `people_analytics.ext_fichajes`
WHERE DATE(timestamp_entrada) = '2026-04-20'
GROUP BY 1, 2;
```

**Ventajas de BigLake:**

| Ventaja | Sin BigLake | Con BigLake |
|---------|------------|-------------|
| Seguridad | Permisos en GCS separados de BQ | Permisos unificados vía IAM |
| Row/Column security | Solo en BQ nativo | También en tablas externas |
| Consulta | Necesita cargar a BQ primero | SQL directo sobre GCS |
| Coste | Almacenamiento doble (GCS + BQ) | Solo GCS |

### Aplicación en People Analytics
- **Fichajes y logs de acceso**: datos voluminosos que no necesitan estar en BigQuery permanentemente. BigLake permite consultarlos cuando sea necesario.
- **Datos históricos archivados**: empleados de años anteriores en Parquet en GCS, consultables sin recargar.
- **CVs y documentos**: si se procesan con NLP, los resultados estructurados van a BigQuery pero los originales quedan en GCS, consultables vía BigLake.

---

## Tema 2.12: Analytics Hub para compartir datasets de forma segura

### Conceptos clave
- **Analytics Hub** permite compartir datasets de BigQuery entre proyectos, departamentos u organizaciones de forma controlada.
- Modelo publisher/subscriber: el equipo de datos **publica** un dataset, y los consumidores (RRHH, Finanzas) **se suscriben**.
- Los datos no se copian — los suscriptores consultan los datos originales con sus propios permisos.

### Detalle técnico

**Flujo de Analytics Hub:**

```
Equipo de datos (publisher)          RRHH (subscriber)            Finanzas (subscriber)
┌───────────────────────┐           ┌───────────────┐            ┌───────────────┐
│ BigQuery              │           │ Su proyecto   │            │ Su proyecto   │
│ gold_metricas_rotacion│──publish──│ linked dataset│            │ linked dataset│
│ gold_headcount        │──────────►│ (solo lectura)│            │ (solo lectura)│
│ gold_brecha_salarial  │           └───────────────┘            └───────────────┘
└───────────────────────┘
         │
    Analytics Hub
    (catálogo central)
```

**Crear un listing en Analytics Hub:**

```sql
-- 1. Crear un Exchange (catálogo)
-- Se hace desde la consola de GCP: Analytics Hub → Create Exchange

-- 2. Crear un Listing (dataset compartido)
-- Analytics Hub → Exchange → Add Listing → Seleccionar dataset BigQuery

-- 3. Los suscriptores ven el listing y se suscriben
-- Reciben un "linked dataset" en su propio proyecto
-- Las queries se ejecutan sobre los datos originales
```

**Ventajas sobre compartir permisos directos:**

| Aspecto | Permisos directos (IAM) | Analytics Hub |
|---------|------------------------|---------------|
| Control | A nivel de dataset/tabla | A nivel de listing (curado) |
| Descubrimiento | El usuario debe conocer el dataset | Catálogo centralizado |
| Gobernanza | Manual, difícil de auditar | Centralizado, con aprobaciones |
| Cross-org | Complejo (requiere org-level policies) | Nativo |
| Coste de queries | El publisher paga | El suscriptor paga sus queries |

### Aplicación en People Analytics
- Publicar datasets Gold curados para que RRHH, Finanzas y Dirección los consuman sin acceder a datos raw.
- Compartir benchmarks salariales anonimizados con otras filiales de la organización.
- Controlar quién tiene acceso a qué métricas: RRHH ve rotación y clima, Finanzas ve coste laboral, Dirección ve todo.

---

## Recursos adicionales

- [Google Cloud Architecture Framework](https://cloud.google.com/architecture/framework)
- [BigQuery best practices](https://cloud.google.com/bigquery/docs/best-practices-performance-overview)
- [Vertex AI Documentation (ES)](https://cloud.google.com/vertex-ai/docs?hl=es)
- [Cloud Architecture Center — Data analytics](https://cloud.google.com/architecture/data-analytics)
- [IAM overview](https://cloud.google.com/iam/docs/overview)
- [BigLake documentation](https://cloud.google.com/biglake/docs)
- [Analytics Hub documentation](https://cloud.google.com/bigquery/docs/analytics-hub-introduction)
- GDPR: Reglamento (UE) 2016/679, especialmente artículos 5, 25, 32
