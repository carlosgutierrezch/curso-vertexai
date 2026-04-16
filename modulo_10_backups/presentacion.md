# Módulo 10: Backups y Recuperación de Datos en GCP

## Información de la sesión
- **Sesión:** 8
- **Fecha:** Lunes 1 de Junio, 17:00–18:00
- **Duración:** ~50 minutos (sesión compartida con Módulo 9)
- **Prerequisitos:** Módulos 1–9 completados, pipeline de Dataform operativo

---

## Tema 10.1: Estrategias de backup en BigQuery

### Conceptos clave
- BigQuery ofrece múltiples mecanismos de protección de datos nativos, desde **time travel** (automático) hasta **snapshots** y **exportaciones** (manuales o automatizadas).
- La estrategia de backup debe estar dimensionada según la criticidad del dato: no todos los datasets necesitan el mismo nivel de protección.
- En People Analytics, los datos son especialmente sensibles (salarios, evaluaciones de desempeño, datos personales) y su pérdida o corrupción puede tener consecuencias legales.
- El principio fundamental es la **regla 3-2-1**: 3 copias del dato, en 2 medios diferentes, con 1 copia fuera del sistema principal.

### Detalle técnico

**Mecanismos de protección en BigQuery:**

| Mecanismo | Tipo | Retención | Coste adicional | Automatización |
|-----------|------|-----------|-----------------|----------------|
| **Time travel** | Nativo automático | 2-7 días (configurable) | Incluido (almacenamiento) | Automático |
| **Fail-safe** | Nativo automático | 7 días adicionales (post time travel) | Incluido | Automático (solo Google) |
| **Table snapshots** | Manual/Programable | Indefinida | Solo almacenamiento delta | Programable |
| **Dataset copy** | Manual/Programable | Indefinida | Almacenamiento completo | Programable |
| **Export a GCS** | Manual/Programable | Según política de GCS | Almacenamiento GCS | Programable |

**Diagrama de capas de protección:**

```
┌───────────────────────────────────────────────────────────┐
│                  CAPAS DE PROTECCIÓN                       │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Capa 1: Time Travel (0-7 días)                       │  │
│  │ - Automático, sin configuración                      │  │
│  │ - Acceso via FOR SYSTEM_TIME AS OF                   │  │
│  │ - Ideal para: "borré filas hace 2 horas"             │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Capa 2: Fail-safe (+7 días, solo Google Support)     │  │
│  │ - Automático, no accesible directamente              │  │
│  │ - Solo recuperable abriendo ticket a Google          │  │
│  │ - Ideal para: desastres graves                       │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Capa 3: Snapshots de tabla (retención configurable)  │  │
│  │ - Manual o programado                                │  │
│  │ - Almacenamiento eficiente (solo delta)              │  │
│  │ - Ideal para: backup mensual pre-deploy              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Capa 4: Exportación a GCS (fuera de BigQuery)        │  │
│  │ - Manual o automatizado (Cloud Scheduler)            │  │
│  │ - Formatos: JSON, Avro, Parquet, CSV                 │  │
│  │ - Ideal para: backup de largo plazo, regla 3-2-1     │  │
│  └──────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

**Clasificación de datos por criticidad en People Analytics:**

| Dataset | Criticidad | Estrategia de backup |
|---------|-----------|---------------------|
| `pa_gold.*` (métricas de negocio) | ALTA | Time travel + snapshot mensual + export trimestral |
| `pa_silver.*` (datos limpios) | ALTA | Time travel + snapshot mensual |
| `pa_bronze.*` (datos crudos) | MEDIA | Time travel + regenerable desde fuente |
| `pa_staging.*` (temporales) | BAJA | Solo time travel (se regeneran) |
| `dim_empleado_historico` (SCD2) | CRITICA | Snapshot semanal + export mensual a GCS |

### Aplicación en People Analytics
- **Datos irrecuperables:** Si se pierde la tabla SCD2 de historial de empleados, reconstruirla desde las fuentes originales puede ser imposible (datos ya no existen en SAP).
- **Cumplimiento legal:** La normativa de protección de datos exige la capacidad de recuperar datos si se identifican borrados incorrectos.
- **Coste del downtime:** Un dashboard de rotación inaccesible durante la reunión mensual del comité de dirección tiene un impacto reputacional significativo para el equipo de datos.

---

## Tema 10.2: Snapshots y recuperación temporal

### Conceptos clave
- El **time travel** de BigQuery permite consultar el estado de una tabla en cualquier momento dentro de la ventana de retención (hasta 7 días).
- Los **table snapshots** son copias de solo lectura de una tabla en un momento específico. Son económicos porque solo almacenan las diferencias respecto a la tabla base.
- La recuperación temporal es la primera línea de defensa ante borrados accidentales, corrupciones de datos o errores en transformaciones.
- La ventana de time travel se configura a nivel de dataset con `max_time_travel_hours`.

### Detalle técnico

**Configurar time travel a 7 días (máximo):**

```sql
-- Configurar time travel a nivel de dataset
ALTER SCHEMA `pa-prod.pa_silver`
SET OPTIONS (
    max_time_travel_hours = 168  -- 7 días x 24 horas
);

ALTER SCHEMA `pa-prod.pa_gold`
SET OPTIONS (
    max_time_travel_hours = 168
);
```

**Consultar datos históricos con FOR SYSTEM_TIME AS OF:**

```sql
-- Ver el estado de la tabla hace 4 horas
SELECT COUNT(*) AS filas, MAX(fecha_snapshot) AS ultimo_snapshot
FROM `pa-prod.pa_silver.silver_empleados`
FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 4 HOUR);

-- Ver el estado de la tabla en una fecha/hora específica
SELECT *
FROM `pa-prod.pa_gold.dim_empleado`
FOR SYSTEM_TIME AS OF TIMESTAMP '2025-03-28 10:00:00 UTC';

-- Comparar estado actual con estado anterior (detectar qué cambió)
WITH actual AS (
    SELECT empleado_id, departamento, salario_bruto
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot = '2025-04-01'
),
anterior AS (
    SELECT empleado_id, departamento, salario_bruto
    FROM `pa-prod.pa_silver.silver_empleados`
    FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
    WHERE fecha_snapshot = '2025-04-01'
)
SELECT
    COALESCE(a.empleado_id, b.empleado_id) AS empleado_id,
    b.departamento AS depto_antes,
    a.departamento AS depto_ahora,
    b.salario_bruto AS salario_antes,
    a.salario_bruto AS salario_ahora
FROM actual a
FULL OUTER JOIN anterior b ON a.empleado_id = b.empleado_id
WHERE a.departamento != b.departamento
    OR a.salario_bruto != b.salario_bruto
    OR a.empleado_id IS NULL
    OR b.empleado_id IS NULL;
```

**Crear y restaurar snapshots de tabla:**

```sql
-- Crear snapshot de una tabla (backup puntual)
CREATE SNAPSHOT TABLE `pa-prod.pa_backups.snapshot_silver_empleados_20250401`
CLONE `pa-prod.pa_silver.silver_empleados`
OPTIONS (
    expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 90 DAY),
    description = 'Backup mensual pre-deploy abril 2025'
);

-- Crear snapshot de una tabla en un momento pasado (time travel + snapshot)
CREATE SNAPSHOT TABLE `pa-prod.pa_backups.snapshot_gold_dim_empleado_antes_fix`
CLONE `pa-prod.pa_gold.dim_empleado`
FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)
OPTIONS (
    description = 'Snapshot antes de aplicar fix de duplicados'
);

-- Restaurar desde snapshot (crear nueva tabla a partir del snapshot)
CREATE OR REPLACE TABLE `pa-prod.pa_silver.silver_empleados`
CLONE `pa-prod.pa_backups.snapshot_silver_empleados_20250401`;

-- Listar todos los snapshots existentes
SELECT
    table_name,
    creation_time,
    TIMESTAMP_MILLIS(last_modified_time) AS last_modified,
    ROUND(size_bytes / 1024 / 1024, 2) AS size_mb
FROM `pa-prod.pa_backups.__TABLES__`
WHERE table_name LIKE 'snapshot_%'
ORDER BY creation_time DESC;
```

### Aplicación en People Analytics
- **Antes de cada deploy:** Crear snapshots de las tablas gold antes de ejecutar Dataform en producción. Si el deploy introduce un error, se puede restaurar en segundos.
- **Investigación de discrepancias:** Cuando un stakeholder dice "el headcount de ayer era diferente", se puede verificar con time travel exactamente qué datos había.
- **Rollback inmediato:** La restauración desde snapshot es instantánea (operación de metadatos en BigQuery), no requiere copiar datos.

---

## Tema 10.3: Exportación de datasets críticos

### Conceptos clave
- La **exportación a Google Cloud Storage (GCS)** proporciona una copia de los datos fuera de BigQuery, cumpliendo con la regla 3-2-1 de backups.
- Los formatos disponibles son: **JSON** (legible), **CSV** (universal), **Avro** (compacto, con schema), **Parquet** (columnar, eficiente).
- Para datasets grandes, BigQuery exporta automáticamente en múltiples archivos con el patrón wildcard (`export-*.parquet`).
- La exportación es una operación gratuita en BigQuery (solo se paga el almacenamiento en GCS).

### Detalle técnico

**Exportar tabla a GCS:**

```sql
-- Exportar a Parquet (recomendado: compacto, tipado, columnar)
EXPORT DATA
OPTIONS (
    uri = 'gs://pa-prod-backups/silver_empleados/2025-04-01/export-*.parquet',
    format = 'PARQUET',
    overwrite = true,
    compression = 'SNAPPY'
)
AS
SELECT *
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot >= '2024-01-01';

-- Exportar a JSON (para auditoría, legible por humanos)
EXPORT DATA
OPTIONS (
    uri = 'gs://pa-prod-backups/gold_dim_empleado/2025-04-01/export-*.json',
    format = 'JSON_NEWLINE_DELIMITED',
    overwrite = true
)
AS
SELECT *
FROM `pa-prod.pa_gold.dim_empleado`;

-- Exportar a Avro (para interoperabilidad con otros sistemas)
EXPORT DATA
OPTIONS (
    uri = 'gs://pa-prod-backups/gold_rotacion/2025-04-01/export-*.avro',
    format = 'AVRO',
    overwrite = true
)
AS
SELECT *
FROM `pa-prod.pa_gold.gold_tasa_rotacion_mensual`;
```

**Estructura recomendada en GCS:**

```
gs://pa-prod-backups/
├── silver_empleados/
│   ├── 2025-01-01/
│   │   └── export-000000000000.parquet
│   ├── 2025-02-01/
│   │   └── export-000000000000.parquet
│   ├── 2025-03-01/
│   │   └── export-000000000000.parquet
│   └── 2025-04-01/
│       └── export-000000000000.parquet
├── gold_dim_empleado/
│   └── 2025-04-01/
│       └── export-000000000000.json
├── gold_dim_empleado_historico/
│   └── 2025-04-01/
│       ├── export-000000000000.parquet
│       └── export-000000000001.parquet
└── metadata/
    └── export_log.json
```

**Restaurar desde GCS a BigQuery:**

```sql
-- Cargar desde Parquet de vuelta a BigQuery
LOAD DATA INTO `pa-prod.pa_silver.silver_empleados`
FROM FILES (
    format = 'PARQUET',
    uris = ['gs://pa-prod-backups/silver_empleados/2025-04-01/export-*.parquet']
);

-- O crear tabla nueva a partir del backup
CREATE TABLE `pa-prod.pa_silver.silver_empleados_restored`
AS
SELECT *
FROM EXTERNAL_QUERY(
    'gs://pa-prod-backups/silver_empleados/2025-04-01/export-*.parquet',
    format = 'PARQUET'
);
```

### Aplicación en People Analytics
- **Retención a largo plazo:** Los datos de empleados deben conservarse según la política de la empresa (generalmente 5-10 años). La exportación a GCS con clases de almacenamiento baratas (Nearline, Coldline) es la opción más económica.
- **Portabilidad:** Los archivos Parquet en GCS son independientes de BigQuery. Si la organización migra a otro cloud o herramienta, los datos están disponibles.
- **Auditoría externa:** Los auditores pueden recibir exportaciones en formato JSON legible, sin necesidad de acceso a BigQuery.

---

## Tema 10.4: Automatización de copias de seguridad

### Conceptos clave
- Los backups manuales son inútiles a largo plazo: se olvidan, se saltan o se hacen incorrectamente. La automatización es obligatoria.
- En GCP, la combinación de **Cloud Scheduler** + **Cloud Functions** permite programar backups automatizados sin infraestructura dedicada.
- Alternativamente, se pueden incluir pasos de backup en el pipeline de Dataform como operaciones previas al deploy.
- Cada ejecución de backup debe registrarse en un log para auditoría.

### Detalle técnico

**Cloud Function para backup automatizado (Python):**

```python
# cloud-functions/fn-backup-bigquery/main.py

import functions_framework
from google.cloud import bigquery
from datetime import datetime, timedelta
import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuración
PROJECT_ID = "pa-prod"
BACKUP_DATASET = "pa_backups"
GCS_BUCKET = "pa-prod-backups"

# Tablas a respaldar con snapshots
TABLAS_SNAPSHOT = [
    {"dataset": "pa_silver", "tabla": "silver_empleados"},
    {"dataset": "pa_gold", "tabla": "dim_empleado"},
    {"dataset": "pa_gold", "tabla": "dim_empleado_historico"},
    {"dataset": "pa_gold", "tabla": "dim_departamento"},
    {"dataset": "pa_gold", "tabla": "fact_rotacion"},
]

# Tablas a exportar a GCS
TABLAS_EXPORT = [
    {"dataset": "pa_gold", "tabla": "dim_empleado_historico", "formato": "PARQUET"},
    {"dataset": "pa_silver", "tabla": "silver_empleados", "formato": "PARQUET"},
]


@functions_framework.http
def backup_bigquery(request):
    """Función principal de backup. Se ejecuta via Cloud Scheduler."""
    client = bigquery.Client(project=PROJECT_ID)
    fecha = datetime.now().strftime("%Y%m%d")
    resultados = []

    # Paso 1: Crear snapshots
    for config in TABLAS_SNAPSHOT:
        try:
            snapshot_name = f"snapshot_{config['tabla']}_{fecha}"
            source = f"`{PROJECT_ID}.{config['dataset']}.{config['tabla']}`"
            destination = f"`{PROJECT_ID}.{BACKUP_DATASET}.{snapshot_name}`"

            # Expiración: 90 días
            expiration = (datetime.now() + timedelta(days=90)).strftime(
                "%Y-%m-%d %H:%M:%S UTC"
            )

            query = f"""
            CREATE SNAPSHOT TABLE {destination}
            CLONE {source}
            OPTIONS (
                expiration_timestamp = TIMESTAMP '{expiration}',
                description = 'Backup automático {fecha}'
            )
            """
            client.query(query).result()
            logger.info(f"Snapshot creado: {snapshot_name}")
            resultados.append({"tabla": config["tabla"],
                               "tipo": "snapshot",
                               "estado": "OK"})
        except Exception as e:
            logger.error(f"Error en snapshot {config['tabla']}: {str(e)}")
            resultados.append({"tabla": config["tabla"],
                               "tipo": "snapshot",
                               "estado": f"ERROR: {str(e)}"})

    # Paso 2: Exportar a GCS
    for config in TABLAS_EXPORT:
        try:
            gcs_uri = (
                f"gs://{GCS_BUCKET}/{config['tabla']}/{fecha}/export-*.parquet"
            )
            source = f"{PROJECT_ID}.{config['dataset']}.{config['tabla']}"

            dataset_ref = bigquery.DatasetReference(PROJECT_ID, config["dataset"])
            table_ref = dataset_ref.table(config["tabla"])

            job_config = bigquery.ExtractJobConfig(
                destination_format=bigquery.DestinationFormat.PARQUET,
                compression=bigquery.Compression.SNAPPY,
            )
            extract_job = client.extract_table(
                table_ref, gcs_uri, job_config=job_config
            )
            extract_job.result()  # Esperar a que termine
            logger.info(f"Export completado: {config['tabla']} -> {gcs_uri}")
            resultados.append({"tabla": config["tabla"],
                               "tipo": "export",
                               "estado": "OK"})
        except Exception as e:
            logger.error(f"Error en export {config['tabla']}: {str(e)}")
            resultados.append({"tabla": config["tabla"],
                               "tipo": "export",
                               "estado": f"ERROR: {str(e)}"})

    # Paso 3: Limpiar snapshots antiguos (> 90 días)
    try:
        cleanup_query = f"""
        SELECT table_name
        FROM `{PROJECT_ID}.{BACKUP_DATASET}.INFORMATION_SCHEMA.TABLES`
        WHERE table_name LIKE 'snapshot_%'
          AND creation_time < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
        """
        rows = client.query(cleanup_query).result()
        for row in rows:
            drop_query = (
                f"DROP SNAPSHOT TABLE IF EXISTS "
                f"`{PROJECT_ID}.{BACKUP_DATASET}.{row.table_name}`"
            )
            client.query(drop_query).result()
            logger.info(f"Snapshot antiguo eliminado: {row.table_name}")
    except Exception as e:
        logger.warning(f"Error en limpieza de snapshots antiguos: {str(e)}")

    return json.dumps({"fecha": fecha, "resultados": resultados}), 200
```

**Programar con Cloud Scheduler:**

```bash
# Crear job de Cloud Scheduler para backup mensual
gcloud scheduler jobs create http backup-bigquery-mensual \
    --location=europe-west1 \
    --schedule="0 4 1 * *" \
    --uri="https://europe-west1-pa-prod.cloudfunctions.net/backup-bigquery" \
    --http-method=POST \
    --oidc-service-account-email=backup-sa@pa-prod.iam.gserviceaccount.com \
    --description="Backup mensual de tablas críticas de People Analytics" \
    --time-zone="Europe/Madrid"

# Crear job para backup semanal de la tabla SCD2 (más crítica)
gcloud scheduler jobs create http backup-scd2-semanal \
    --location=europe-west1 \
    --schedule="0 3 * * 1" \
    --uri="https://europe-west1-pa-prod.cloudfunctions.net/backup-bigquery" \
    --http-method=POST \
    --body='{"only_tables": ["dim_empleado_historico"]}' \
    --oidc-service-account-email=backup-sa@pa-prod.iam.gserviceaccount.com \
    --description="Backup semanal de dimensión SCD2" \
    --time-zone="Europe/Madrid"
```

**Integrar backup en Dataform (pre-deploy):**

```sqlx
-- definitions/operations/op_backup_pre_deploy.sqlx

config {
    type: "operations",
    schema: "pa_backups",
    description: "Crear snapshots de tablas críticas antes del deploy mensual",
    tags: ["backup", "pre-deploy"],
    hasOutput: false
}

-- Snapshot de silver_empleados
CREATE SNAPSHOT TABLE IF NOT EXISTS
    `pa-prod.pa_backups.snapshot_silver_empleados_${dataform.projectConfig.vars.fecha_corte}`
CLONE `pa-prod.pa_silver.silver_empleados`
OPTIONS (
    expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 90 DAY),
    description = 'Pre-deploy backup ${dataform.projectConfig.vars.fecha_corte}'
);

---

-- Snapshot de dim_empleado_historico
CREATE SNAPSHOT TABLE IF NOT EXISTS
    `pa-prod.pa_backups.snapshot_dim_empleado_hist_${dataform.projectConfig.vars.fecha_corte}`
CLONE `pa-prod.pa_gold.dim_empleado_historico`
OPTIONS (
    expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 180 DAY),
    description = 'Pre-deploy backup ${dataform.projectConfig.vars.fecha_corte}'
);
```

### Aplicación en People Analytics
- **Sin intervención humana:** Los backups se ejecutan automáticamente cada mes (o semana para tablas críticas), sin depender de que alguien lo recuerde.
- **Pre-deploy safety net:** Antes de cada ejecución de Dataform en producción, se crean snapshots automáticos. Si algo sale mal, la restauración es inmediata.
- **Registro de auditoría:** Cada ejecución de backup genera un log con el resultado, proporcionando evidencia de cumplimiento.

---

## Tema 10.5: Políticas de retención de datos

### Conceptos clave
- Las **políticas de retención** definen cuánto tiempo se conservan los datos, equilibrando las necesidades analíticas con las obligaciones legales y el coste de almacenamiento.
- El **RGPD (Art. 5.1.e)** establece el principio de limitación del plazo de conservación: los datos personales no se pueden guardar indefinidamente sin justificación.
- En BigQuery, la retención se gestiona mediante **partition expiration**, **table expiration** y políticas de borrado.
- Las tablas de People Analytics contienen datos personales (nombre, salario, evaluaciones), por lo que las políticas de retención son especialmente relevantes.

### Detalle técnico

**Configurar expiración de particiones:**

```sql
-- Las particiones de más de 2 años se eliminan automáticamente
ALTER TABLE `pa-prod.pa_silver.silver_empleados`
SET OPTIONS (
    partition_expiration_days = 730  -- 2 años
);

-- Para bronze: retención más corta (regenerable desde fuente)
ALTER TABLE `pa-prod.pa_bronze.bronze_empleados`
SET OPTIONS (
    partition_expiration_days = 365  -- 1 año
);

-- Para gold: retención más larga (métricas históricas)
ALTER TABLE `pa-prod.pa_gold.fact_rotacion`
SET OPTIONS (
    partition_expiration_days = 1825  -- 5 años
);
```

**Política de retención por tipo de dato:**

| Tipo de dato | Retención BigQuery | Backup GCS | Justificación legal |
|-------------|-------------------|------------|-------------------|
| Datos crudos (bronze) | 1 año | No | Regenerable desde fuente |
| Datos limpios (silver) | 2 años | 5 años (Coldline) | Análisis retroactivo |
| Métricas agregadas (gold) | 5 años | 10 años (Archive) | Reporting regulatorio |
| Historial SCD2 | Indefinido | 10 años | Auditoría salarial |
| Datos de evaluación | 3 años | 5 años | Normativa laboral |
| Datos sensibles (salario) | 5 años post-baja | 5 años | RGPD + normativa fiscal |

**Borrado selectivo para cumplimiento RGPD (derecho al olvido):**

```sql
-- Si un ex-empleado ejerce su derecho de supresión,
-- borrar sus datos personales manteniendo los agregados

-- Paso 1: Anonimizar en silver (no borrar, anonimizar)
UPDATE `pa-prod.pa_silver.silver_empleados`
SET
    nombre_completo = 'ANONIMIZADO',
    email = NULL,
    telefono = NULL,
    direccion = NULL,
    -- Mantener datos no identificativos para análisis
    -- departamento, nivel, salario (ya no es identificativo sin nombre)
    fecha_anonimizacion = CURRENT_TIMESTAMP()
WHERE empleado_id = 'EMP-XXXX';

-- Paso 2: Anonimizar en gold
UPDATE `pa-prod.pa_gold.dim_empleado_historico`
SET
    nombre_completo = 'ANONIMIZADO',
    is_anonimizado = TRUE
WHERE empleado_id = 'EMP-XXXX';

-- Paso 3: Registrar la acción para auditoría
INSERT INTO `pa-prod.pa_gold.log_anonimizaciones`
VALUES (
    'EMP-XXXX',
    CURRENT_TIMESTAMP(),
    'Derecho de supresión RGPD',
    SESSION_USER()
);
```

### Aplicación en People Analytics
- **RGPD compliance:** Las políticas de retención documentadas y automatizadas son un requisito del RGPD. Sin ellas, la organización se expone a multas.
- **Optimización de costes:** Los datos de bronze de más de 1 año se eliminan automáticamente, ahorrando almacenamiento.
- **Derecho al olvido:** El proceso de anonimización permite cumplir con solicitudes de borrado sin destruir la integridad de las métricas agregadas.

---

## Tema 10.6: Recuperación ante borrado accidental

### Conceptos clave
- El **borrado accidental** es el incidente de datos más común: un `DELETE` sin WHERE, un `DROP TABLE` por error, o una transformación de Dataform que sobrescribe datos incorrectamente.
- La **velocidad de recuperación** (RTO - Recovery Time Objective) determina qué mecanismo usar: time travel (segundos), snapshot (minutos), GCS (horas).
- Cada mecanismo tiene su ventana de disponibilidad: time travel funciona hasta 7 días, los snapshots hasta su expiración, y las exportaciones en GCS de forma indefinida.
- Es fundamental tener un **runbook** documentado con los pasos exactos para cada escenario de recuperación.

### Detalle técnico

**Escenario 1 — Borrado accidental de filas (< 7 días):**

```sql
-- Un analista ejecutó accidentalmente:
-- DELETE FROM pa_silver.silver_empleados WHERE fecha_snapshot = '2025-04-01'

-- Recuperación via Time Travel:
-- Paso 1: Verificar que los datos existían antes del borrado
SELECT COUNT(*) AS filas_antes
FROM `pa-prod.pa_silver.silver_empleados`
FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
WHERE fecha_snapshot = '2025-04-01';

-- Paso 2: Restaurar las filas borradas
INSERT INTO `pa-prod.pa_silver.silver_empleados`
SELECT *
FROM `pa-prod.pa_silver.silver_empleados`
FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
WHERE fecha_snapshot = '2025-04-01'
AND empleado_id NOT IN (
    -- Excluir filas que aún existen (por si solo se borró parcialmente)
    SELECT empleado_id
    FROM `pa-prod.pa_silver.silver_empleados`
    WHERE fecha_snapshot = '2025-04-01'
);
```

**Escenario 2 — DROP TABLE accidental (< 7 días):**

```sql
-- Un analista ejecutó: DROP TABLE pa_gold.dim_empleado

-- Recuperación via Time Travel (la tabla "borrada" aún existe en time travel):
-- Opción A: Copiar desde time travel a tabla nueva
CREATE TABLE `pa-prod.pa_gold.dim_empleado` AS
SELECT *
FROM `pa-prod.pa_gold.dim_empleado`
FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 MINUTE);

-- Opción B: Si existe un snapshot reciente
CREATE TABLE `pa-prod.pa_gold.dim_empleado`
CLONE `pa-prod.pa_backups.snapshot_dim_empleado_20250401`;
```

**Escenario 3 — Corrupción de datos por transformación incorrecta:**

```sql
-- Dataform ejecutó una transformación que sobrescribió silver_empleados
-- con datos incorrectos (e.g., salarios multiplicados por 100)

-- Paso 1: Verificar con time travel
SELECT AVG(salario_bruto) AS salario_medio_actual
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2025-04-01';
-- Resultado: 3,500,000 (incorrecto)

SELECT AVG(salario_bruto) AS salario_medio_antes
FROM `pa-prod.pa_silver.silver_empleados`
FOR SYSTEM_TIME AS OF TIMESTAMP '2025-04-01 05:00:00 UTC'
WHERE fecha_snapshot = '2025-04-01';
-- Resultado: 35,000 (correcto)

-- Paso 2: Restaurar tabla completa desde time travel
CREATE OR REPLACE TABLE `pa-prod.pa_silver.silver_empleados` AS
SELECT *
FROM `pa-prod.pa_silver.silver_empleados`
FOR SYSTEM_TIME AS OF TIMESTAMP '2025-04-01 05:00:00 UTC';

-- Paso 3: Reejecutar Dataform desde silver hacia gold
-- (las tablas gold se regenerarán con los datos corregidos)
```

**Runbook de recuperación (resumen):**

```
┌─────────────────────────────────────────────────────────┐
│             RUNBOOK: RECUPERACIÓN DE DATOS                │
│                                                          │
│  ¿Cuándo ocurrió el incidente?                           │
│  │                                                       │
│  ├── Hace < 7 días ──> Usar TIME TRAVEL                  │
│  │   └── FOR SYSTEM_TIME AS OF [timestamp]               │
│  │                                                       │
│  ├── Hace 7-14 días ──> Contactar Google Support         │
│  │   └── Fail-safe (solo Google puede acceder)           │
│  │                                                       │
│  ├── Hay snapshot disponible ──> Usar SNAPSHOT            │
│  │   └── CLONE desde pa_backups.snapshot_*               │
│  │                                                       │
│  └── Hay export en GCS ──> Restaurar desde GCS           │
│      └── LOAD DATA FROM FILES gs://pa-prod-backups/...   │
│                                                          │
│  POST-RECUPERACIÓN:                                      │
│  1. Verificar integridad de los datos restaurados        │
│  2. Reejecutar Dataform (silver → gold)                  │
│  3. Verificar dashboards                                 │
│  4. Documentar el incidente en el CHANGELOG              │
│  5. Implementar medida preventiva (si aplica)            │
└─────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- **RTO de minutos:** Con time travel y snapshots, la recuperación de datos de People Analytics toma minutos, no horas o días.
- **Documentación del incidente:** Cada recuperación debe documentarse: qué pasó, quién lo causó, cómo se recuperó, y qué se hizo para prevenir que vuelva a ocurrir.
- **Prevención:** Después de cada incidente, evaluar si se necesitan controles adicionales (permisos más restrictivos, assertions más estrictas, protección contra DELETE sin WHERE).

---

## Temas 10.7–10.10: Separación de entornos, pruebas, seguridad y continuidad

### Conceptos clave
- La **separación de backups por entorno** garantiza que los backups de producción estén aislados del entorno de desarrollo.
- Las **pruebas de restauración** periódicas validan que los backups realmente funcionan (un backup que no se ha probado no es un backup).
- La **seguridad de los backups** requiere cifrado, control de acceso y auditoría de quién accede a las copias.
- El **plan de continuidad** define los procedimientos para mantener la operación en caso de fallo mayor.

### Detalle técnico

**Separación de backups por entorno:**

```
Proyecto pa-prod (producción):
├── Dataset: pa_backups
│   ├── snapshot_silver_empleados_20250401
│   ├── snapshot_dim_empleado_20250401
│   └── ...
├── Bucket GCS: gs://pa-prod-backups/
│   ├── silver_empleados/
│   └── gold_dim_empleado_historico/

Proyecto pa-dev (desarrollo):
├── Dataset: pa_backups_dev
│   └── (snapshots de dev, si son necesarios)
├── Bucket GCS: gs://pa-dev-backups/
│   └── (solo para pruebas de restauración)

REGLA: Los backups de producción NUNCA se almacenan en el proyecto de desarrollo.
```

**Script de prueba de restauración mensual:**

```bash
#!/bin/bash
# scripts/test-restore.sh
# Ejecutar mensualmente para verificar que los backups son restaurables

set -e

PROJECT="pa-prod"
BACKUP_DATASET="pa_backups"
TEST_DATASET="pa_restore_test"
FECHA=$(date +%Y%m%d)

echo "=== PRUEBA DE RESTAURACIÓN: $FECHA ==="

# 1. Crear dataset temporal para la prueba
bq mk --dataset \
    --description "Dataset temporal para prueba de restauración" \
    --default_table_expiration 86400 \
    "$PROJECT:$TEST_DATASET"

# 2. Restaurar snapshot más reciente
LATEST_SNAPSHOT=$(bq ls "$PROJECT:$BACKUP_DATASET" | grep "snapshot_silver_empleados" | sort -r | head -1 | awk '{print $1}')
echo "Restaurando snapshot: $LATEST_SNAPSHOT"

bq cp "$PROJECT:$BACKUP_DATASET.$LATEST_SNAPSHOT" \
    "$PROJECT:$TEST_DATASET.silver_empleados_restored"

# 3. Verificar integridad
echo "Verificando integridad..."
ROWS=$(bq query --nouse_legacy_sql --format=csv \
    "SELECT COUNT(*) AS n FROM \`$PROJECT.$TEST_DATASET.silver_empleados_restored\`" \
    | tail -1)
echo "Filas restauradas: $ROWS"

if [ "$ROWS" -gt 0 ]; then
    echo "PRUEBA EXITOSA: Snapshot restaurable con $ROWS filas"
else
    echo "ERROR: Snapshot vacío o corrupto"
    exit 1
fi

# 4. Verificar exportación GCS
LATEST_EXPORT=$(gsutil ls "gs://pa-prod-backups/silver_empleados/" | sort -r | head -1)
echo "Verificando exportación GCS: $LATEST_EXPORT"

bq load --source_format=PARQUET \
    "$PROJECT:$TEST_DATASET.silver_empleados_from_gcs" \
    "${LATEST_EXPORT}export-*.parquet"

GCS_ROWS=$(bq query --nouse_legacy_sql --format=csv \
    "SELECT COUNT(*) AS n FROM \`$PROJECT.$TEST_DATASET.silver_empleados_from_gcs\`" \
    | tail -1)
echo "Filas desde GCS: $GCS_ROWS"

# 5. Limpiar
bq rm -r -f "$PROJECT:$TEST_DATASET"

echo "=== PRUEBA COMPLETADA ==="
echo "Snapshot: $ROWS filas | GCS: $GCS_ROWS filas"
```

**Seguridad de backups — Control de acceso:**

```bash
# Solo el service account de backup puede escribir en el dataset de backups
bq update --set_label=backup:true "$PROJECT:$BACKUP_DATASET"

# IAM: Solo lectura para el equipo, escritura solo para el SA de backup
gcloud projects add-iam-policy-binding pa-prod \
    --member="serviceAccount:backup-sa@pa-prod.iam.gserviceaccount.com" \
    --role="roles/bigquery.dataEditor" \
    --condition="expression=resource.name.startsWith('projects/pa-prod/datasets/pa_backups'),title=solo-backup-dataset"

# GCS: Bucket con retención mínima (no se puede borrar antes del plazo)
gsutil retention set 30d gs://pa-prod-backups/
gsutil retention lock gs://pa-prod-backups/

# Cifrado: Usar CMEK (Customer Managed Encryption Key) para datos sensibles
gcloud kms keys create pa-backup-key \
    --location=europe-west1 \
    --keyring=pa-keyring \
    --purpose=encryption

gsutil kms authorize -p pa-prod -k \
    projects/pa-prod/locations/europe-west1/keyRings/pa-keyring/cryptoKeys/pa-backup-key
```

**Plan de continuidad resumido:**

| Escenario | RTO | RPO | Acción |
|-----------|-----|-----|--------|
| Borrado de filas | 5 min | 0 (time travel) | Restaurar con FOR SYSTEM_TIME AS OF |
| DROP TABLE | 10 min | 0-7 días | Time travel o snapshot |
| Corrupción de datos | 30 min | Último snapshot | Restaurar snapshot + reejecutar Dataform |
| Fallo de BigQuery regional | 4 horas | Última exportación GCS | Restaurar en otra región desde GCS |
| Pérdida total del proyecto GCP | 24 horas | Última exportación GCS | Recrear proyecto + restaurar desde GCS |

### Aplicación en People Analytics
- **Pruebas trimestrales:** Ejecutar la prueba de restauración al menos cada trimestre. Documentar el resultado para auditoría.
- **Segregación de responsabilidades:** El analista que ejecuta Dataform no debería poder borrar backups. Usar IAM para separar roles.
- **Datos sensibles:** Los backups contienen los mismos datos sensibles que las tablas originales. Aplicar el mismo nivel de cifrado y control de acceso.
- **Plan de continuidad documentado:** El runbook debe estar accesible al equipo completo (no solo al lead). Idealmente, en el repositorio de GitHub bajo `docs/runbooks/`.

---

## Resumen del módulo

| Tema | Concepto clave | Herramienta GCP |
|------|---------------|----------------|
| 10.1 | Estrategias de backup | Time travel, snapshots, GCS |
| 10.2 | Recuperación temporal | FOR SYSTEM_TIME AS OF, CLONE |
| 10.3 | Exportación a GCS | EXPORT DATA, Parquet/Avro |
| 10.4 | Automatización | Cloud Scheduler + Cloud Functions |
| 10.5 | Retención RGPD | Partition expiration, anonimización |
| 10.6 | Recuperación ante borrado | Runbook, time travel, snapshots |
| 10.7-10.10 | Continuidad y seguridad | IAM, CMEK, pruebas de restauración |

---

## Preparación para el siguiente módulo

En el **Módulo 11: Gobierno y Seguridad del Dato**, profundizaremos en los controles de acceso granular a nivel de fila y columna en BigQuery, el cumplimiento de la RGPD aplicado a datos de empleados, y las auditorías de acceso.
