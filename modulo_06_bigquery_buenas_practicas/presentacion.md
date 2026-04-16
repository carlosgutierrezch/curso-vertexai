# Módulo 6: Buenas Prácticas de BigQuery para Ingenieros de Datos

## Información de la sesión
- **Sesión:** 5
- **Fecha:** Lunes 11 de Mayo, 16:00–18:00
- **Duración:** 2 horas (sesión completa — módulo más denso del curso)
- **Prerequisitos:** Módulos 1–5 completados

---

## Tema 6.1: Modelado de datasets en entornos productivos

### Conceptos clave
- Un **dataset** en BigQuery es un contenedor lógico de tablas, vistas y rutinas dentro de un proyecto.
- La organización de datasets refleja la arquitectura de datos: separar por capa (bronze/silver/gold), por dominio o por nivel de acceso.
- En producción, el modelado de datasets es una decisión de **gobernanza**, no solo técnica.

### Detalle técnico

**Estrategias de organización:**

| Estrategia | Estructura | Ventaja | Inconveniente |
|------------|-----------|---------|---------------|
| **Por capa (medallion)** | `bronze`, `silver`, `gold` | Clara separación de calidad | Muchas tablas por dataset |
| **Por dominio** | `empleados`, `evaluaciones`, `nomina` | Permisos por dominio | No separa calidad |
| **Híbrida (recomendada)** | `pa_bronze`, `pa_silver`, `pa_gold` | Lo mejor de ambos | Nomenclatura más larga |

**Nomenclatura recomendada:**

```
proyecto: pa-prod
├── pa_bronze              (datos crudos, ingesta directa)
│   ├── bronze_empleados
│   ├── bronze_nomina
│   └── bronze_evaluaciones
├── pa_silver              (datos limpios, normalizados)
│   ├── silver_empleados
│   ├── silver_nomina
│   └── silver_evaluaciones
├── pa_gold                (métricas de negocio, consumo)
│   ├── gold_rotacion_mensual
│   ├── gold_brecha_salarial
│   ├── gold_headcount
│   ├── dim_empleado
│   ├── dim_departamento
│   └── fact_evaluacion
└── pa_staging             (tablas temporales de Dataform)
    └── stg_*
```

---

## Tema 6.2: Particionado y clustering eficiente

### Conceptos clave
- **Particionado** divide una tabla en segmentos por una columna (generalmente fecha). BigQuery solo escanea las particiones necesarias → menos datos procesados → menor coste.
- **Clustering** ordena los datos dentro de cada partición por hasta 4 columnas. Mejora rendimiento en filtros frecuentes.
- Son las dos herramientas más importantes para controlar coste y rendimiento.

### Detalle técnico

**Tipos de particionado:**

| Tipo | Columna | Ejemplo PA | Uso |
|------|---------|------------|-----|
| **Por fecha/timestamp** | `DATE`, `TIMESTAMP`, `DATETIME` | `fecha_snapshot` | Datos con dimensión temporal (el más común) |
| **Por rango de enteros** | `INTEGER` | `antiguedad_meses` (rangos de 12) | Datos segmentados por rangos numéricos |
| **Por tiempo de ingesta** | `_PARTITIONTIME` (auto) | Cualquier tabla | Cuando no hay columna de fecha adecuada |

**Crear tabla particionada y clusterizada:**

```sql
-- Tabla de empleados: particionada por fecha, clusterizada por departamento y nivel
CREATE TABLE `pa-prod.pa_silver.silver_empleados`
(
    empleado_id STRING NOT NULL,
    fecha_snapshot DATE NOT NULL,
    departamento STRING,
    nivel STRING,
    ciudad STRING,
    genero STRING,
    edad INT64,
    antiguedad_meses INT64,
    salario_bruto INT64,
    meses_sin_promocion INT64,
    rating_desempeno INT64,
    score_clima FLOAT64,
    dias_absentismo INT64,
    horas_formacion INT64,
    rotacion BOOL,
    fecha_baja DATE
)
PARTITION BY fecha_snapshot
CLUSTER BY departamento, nivel, ciudad
OPTIONS (
    description = "Datos de empleados limpios y normalizados",
    require_partition_filter = true,  -- OBLIGATORIO: evita full scans
    partition_expiration_days = 730,   -- Retener 2 años
    labels = [("dominio", "people_analytics"), ("capa", "silver")]
);
```

**Reglas de oro para clustering:**

| Regla | Detalle |
|-------|---------|
| **Máximo 4 columnas** | BigQuery solo permite 4 columnas de clustering |
| **Orden importa** | La primera columna es la más efectiva. Ordenar por cardinalidad ascendente |
| **Columnas filtradas frecuentemente** | Solo clusterizar por columnas usadas en WHERE |
| **No clusterizar columnas de alta cardinalidad** | `empleado_id` tiene 2.000 valores → no ideal como primera columna |

**Orden de clustering recomendado para tabla de empleados:**

```
CLUSTER BY departamento, nivel, ciudad
-- departamento: 8 valores (baja cardinalidad, filtro frecuente)
-- nivel: 6 valores (baja cardinalidad, filtro frecuente) 
-- ciudad: 6 valores (filtro ocasional)
-- NO incluir genero (análisis sesgado) ni empleado_id (alta cardinalidad)
```

**Impacto en costes (ejemplo real):**

```sql
-- Sin particionado ni clustering:
-- SELECT * FROM empleados WHERE departamento = 'Tecnología'
-- → Escanea TODA la tabla: 50 GB → $0.31

-- Con particionado por fecha:
-- SELECT * FROM empleados WHERE fecha_snapshot = '2026-05-01' AND departamento = 'Tecnología'
-- → Escanea 1 partición: 0.5 GB → $0.003

-- Con particionado + clustering:
-- → Escanea solo bloques del departamento 'Tecnología': 0.06 GB → $0.0004

-- Ahorro: 99.87% de coste
```

---

## Tema 6.3: Control de costes por consulta

### Detalle técnico

**INFORMATION_SCHEMA para monitorizar costes:**

```sql
-- Top 20 queries más caras del último mes
SELECT
    user_email,
    job_id,
    query,
    ROUND(total_bytes_processed / POW(1024, 3), 2) AS gb_procesados,
    ROUND(total_bytes_processed / POW(1024, 4) * 6.25, 4) AS coste_usd,
    total_slot_ms / 1000 AS slot_seconds,
    TIMESTAMP_DIFF(end_time, start_time, SECOND) AS duracion_segundos,
    creation_time
FROM `region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
    AND total_bytes_processed > 0
ORDER BY total_bytes_processed DESC
LIMIT 20;

-- Coste acumulado por usuario
SELECT
    user_email,
    COUNT(*) AS num_queries,
    ROUND(SUM(total_bytes_processed) / POW(1024, 4), 4) AS tb_total,
    ROUND(SUM(total_bytes_processed) / POW(1024, 4) * 6.25, 2) AS coste_total_usd,
    ROUND(AVG(total_bytes_processed) / POW(1024, 3), 2) AS gb_promedio_por_query
FROM `region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
GROUP BY user_email
ORDER BY coste_total_usd DESC;
```

**Dry run para estimar coste antes de ejecutar:**

```python
from google.cloud import bigquery

client = bigquery.Client()

query = """
SELECT * FROM `pa-prod.pa_gold.gold_rotacion_mensual`
WHERE fecha_snapshot BETWEEN '2025-01-01' AND '2026-01-01'
"""

# Dry run: estima bytes sin ejecutar
job_config = bigquery.QueryJobConfig(dry_run=True, use_query_cache=False)
query_job = client.query(query, job_config=job_config)

gb = query_job.total_bytes_processed / (1024 ** 3)
coste = query_job.total_bytes_processed / (1024 ** 4) * 6.25

print(f"Esta query procesará {gb:.2f} GB → coste estimado: ${coste:.4f}")
```

---

## Tema 6.4: Optimización de rendimiento en tablas grandes

### Detalle técnico

**Checklist de optimización:**

| Técnica | Impacto | Implementación |
|---------|---------|----------------|
| **Evitar SELECT *** | Alto | Seleccionar solo columnas necesarias |
| **Filtrar por partición** | Alto | Siempre incluir `WHERE fecha_snapshot = ...` |
| **Usar vistas materializadas** | Alto | Para queries frecuentes y costosas |
| **Evitar JOINs sobre tablas completas** | Medio | Pre-filtrar antes del JOIN |
| **Usar APPROX_COUNT_DISTINCT** | Medio | En lugar de COUNT(DISTINCT) para estimaciones |
| **Evitar ORDER BY sin LIMIT** | Medio | BigQuery ordena todos los datos |
| **Usar WITH (CTEs) en vez de subconsultas correlacionadas** | Medio | CTEs se materializan una vez |

**Vistas materializadas:**

```sql
-- Vista materializada: tasa de rotación por departamento (se refresca automáticamente)
CREATE MATERIALIZED VIEW `pa-prod.pa_gold.mv_rotacion_por_depto`
OPTIONS (
    enable_refresh = true,
    refresh_interval_minutes = 60  -- Refrescar cada hora
)
AS
SELECT
    fecha_snapshot,
    departamento,
    COUNT(*) AS total_empleados,
    COUNTIF(rotacion = TRUE) AS bajas,
    ROUND(COUNTIF(rotacion = TRUE) * 100.0 / COUNT(*), 1) AS tasa_rotacion_pct,
    ROUND(AVG(salario_bruto), 0) AS salario_medio,
    ROUND(AVG(score_clima), 1) AS clima_medio
FROM `pa-prod.pa_silver.silver_empleados`
GROUP BY fecha_snapshot, departamento;
```

---

## Tema 6.5: Gestión de permisos a nivel dataset y tabla

### Detalle técnico

```python
from google.cloud import bigquery

client = bigquery.Client()

# Permisos a nivel dataset
dataset_ref = client.dataset("pa_gold")
dataset = client.get_dataset(dataset_ref)

# Añadir acceso de lectura para el grupo de RRHH
access_entries = list(dataset.access_entries)
access_entries.append(
    bigquery.AccessEntry(
        role="READER",
        entity_type="groupByEmail",
        entity_id="rrhh-analytics@empresa.com",
    )
)
dataset.access_entries = access_entries
client.update_dataset(dataset, ["access_entries"])

# Permisos a nivel tabla (requiere IAM policy)
from google.iam.v1 import policy_pb2

table_ref = "pa-prod.pa_gold.gold_brecha_salarial"
table = client.get_table(table_ref)

policy = client.get_iam_policy(table)
policy.bindings.add(
    role="roles/bigquery.dataViewer",
    members=["group:rrhh-compensacion@empresa.com"],
)
client.set_iam_policy(table, policy)
```

---

## Tema 6.6: Uso de tablas intermedias y capas semánticas

### Detalle técnico

**Patrón de capas semánticas:**

```
Capa Bronze (raw)        Capa Silver (clean)       Capa Gold (business)
┌─────────────────┐      ┌─────────────────┐      ┌──────────────────────┐
│bronze_empleados │      │silver_empleados │      │gold_rotacion_mensual │
│(datos crudos    │─────►│(limpio,         │─────►│(tasa rotación por    │
│del HRIS)        │      │normalizado,     │      │depto, nivel, mes)    │
│                 │      │tipado)          │      │                      │
└─────────────────┘      └─────────────────┘      │gold_brecha_salarial  │
                                                   │(brecha por nivel,    │
Capa Staging              Capa Dimensiones         │género, controlada)   │
┌─────────────────┐      ┌─────────────────┐      │                      │
│stg_empleados_   │      │dim_empleado     │      │gold_headcount        │
│dedup            │      │dim_departamento │      │(headcount activo     │
│(deduplicación   │      │dim_tiempo       │      │por mes)              │
│temporal)        │      │dim_nivel        │      └──────────────────────┘
└─────────────────┘      └─────────────────┘
```

---

## Tema 6.7: Estrategias de versionado de tablas

### Detalle técnico

```sql
-- Estrategia 1: Sufijo de versión
-- pa_gold.gold_rotacion_mensual_v1
-- pa_gold.gold_rotacion_mensual_v2 (nueva lógica)
-- pa_gold.gold_rotacion_mensual    (vista que apunta a la versión activa)

CREATE OR REPLACE VIEW `pa-prod.pa_gold.gold_rotacion_mensual` AS
SELECT * FROM `pa-prod.pa_gold.gold_rotacion_mensual_v2`;
-- Cambiar de v2 a v3: solo actualizar la vista

-- Estrategia 2: Table snapshots para rollback
CREATE SNAPSHOT TABLE `pa-prod.pa_gold.snapshot_rotacion_20260511`
CLONE `pa-prod.pa_gold.gold_rotacion_mensual`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY));
```

---

## Tema 6.8: Gestión de datos históricos y snapshots

### Detalle técnico

```sql
-- Time travel: acceder a datos de hasta 7 días atrás
SELECT * FROM `pa-prod.pa_silver.silver_empleados`
FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 DAY)
WHERE fecha_snapshot = '2026-05-01';

-- Crear snapshot explícito antes de una migración
CREATE SNAPSHOT TABLE `pa-prod.pa_gold.backup_pre_migracion_20260511`
CLONE `pa-prod.pa_gold.gold_rotacion_mensual`;

-- Restaurar desde snapshot
CREATE OR REPLACE TABLE `pa-prod.pa_gold.gold_rotacion_mensual`
CLONE `pa-prod.pa_gold.backup_pre_migracion_20260511`;
```

---

## Tema 6.9–6.10: Documentación técnica y auditoría de consultas

### Detalle técnico

```sql
-- Documentar tabla con OPTIONS
ALTER TABLE `pa-prod.pa_silver.silver_empleados`
SET OPTIONS (
    description = "Datos de empleados limpios. Fuente: SAP SF. Actualización: diaria 07:00. Responsable: equipo PA.",
    labels = [("dominio", "people_analytics"), ("pii", "true"), ("capa", "silver")]
);

-- Documentar columnas
ALTER TABLE `pa-prod.pa_silver.silver_empleados`
ALTER COLUMN salario_bruto SET OPTIONS (
    description = "Salario bruto anual en euros. Dato sensible — acceso restringido."
);

-- Auditoría: queries sobre datos sensibles en los últimos 7 días
SELECT
    user_email,
    query,
    creation_time,
    total_bytes_processed
FROM `region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND REGEXP_CONTAINS(query, r'(?i)(salario|genero|edad|discapacidad)')
ORDER BY creation_time DESC;
```

---

## Tema 6.11: Stored Procedures para encapsular lógica compleja

### Detalle técnico

```sql
-- Stored Procedure: calcular headcount activo a una fecha
CREATE OR REPLACE PROCEDURE `pa-prod.pa_gold.sp_calcular_headcount`(
    IN p_fecha DATE,
    IN p_dataset STRING
)
BEGIN
    -- Borrar datos existentes (idempotencia)
    EXECUTE IMMEDIATE FORMAT("""
        DELETE FROM `%s.gold_headcount` WHERE fecha_snapshot = '%t'
    """, p_dataset, p_fecha);
    
    -- Calcular headcount
    EXECUTE IMMEDIATE FORMAT("""
        INSERT INTO `%s.gold_headcount`
        SELECT
            '%t' AS fecha_snapshot,
            departamento,
            nivel,
            genero,
            COUNT(*) AS headcount,
            COUNT(CASE WHEN rotacion = FALSE THEN 1 END) AS activos,
            COUNT(CASE WHEN rotacion = TRUE THEN 1 END) AS bajas,
            ROUND(AVG(salario_bruto), 0) AS salario_medio,
            ROUND(AVG(antiguedad_meses), 0) AS antiguedad_media
        FROM `%s.silver_empleados`
        WHERE fecha_snapshot = '%t'
        GROUP BY departamento, nivel, genero
    """, p_dataset, p_fecha, p_dataset, p_fecha);
    
    -- Log
    SELECT FORMAT("Headcount calculado para %t: %%d registros", p_fecha, @@row_count);
END;

-- Ejecutar
CALL `pa-prod.pa_gold.sp_calcular_headcount`('2026-05-01', 'pa-prod.pa_gold');
```

---

## Tema 6.12: User Defined Functions (UDFs) reutilizables

### Detalle técnico

```sql
-- UDF SQL: clasificar riesgo de rotación
CREATE OR REPLACE FUNCTION `pa-prod.pa_gold.fn_riesgo_rotacion`(
    meses_sin_promocion INT64,
    score_clima FLOAT64,
    dias_absentismo INT64
) AS (
    CASE
        WHEN meses_sin_promocion > 36 AND score_clima < 5 AND dias_absentismo > 15 THEN 'CRÍTICO'
        WHEN meses_sin_promocion > 24 AND score_clima < 6 THEN 'ALTO'
        WHEN meses_sin_promocion > 12 OR score_clima < 7 THEN 'MEDIO'
        ELSE 'BAJO'
    END
);

-- Uso
SELECT
    empleado_id,
    departamento,
    `pa-prod.pa_gold.fn_riesgo_rotacion`(meses_sin_promocion, score_clima, dias_absentismo) AS riesgo
FROM `pa-prod.pa_silver.silver_empleados`
WHERE fecha_snapshot = '2026-05-01' AND rotacion = FALSE;

-- UDF JavaScript: normalizar texto de evaluaciones
CREATE OR REPLACE FUNCTION `pa-prod.pa_gold.fn_normalizar_texto`(texto STRING)
RETURNS STRING
LANGUAGE js AS r"""
    if (!texto) return null;
    return texto
        .toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')  // Quitar acentos
        .replace(/[^a-z0-9\s]/g, '')       // Solo alfanuméricos
        .replace(/\s+/g, ' ')              // Espacios múltiples → uno
        .trim();
""";
```

---

## Tema 6.13: Uso de Procedural Language en BigQuery

### Detalle técnico

```sql
-- Script procedimental: procesar datos de múltiples meses
DECLARE fecha_inicio DATE DEFAULT '2026-01-01';
DECLARE fecha_fin DATE DEFAULT '2026-05-01';
DECLARE fecha_actual DATE;
DECLARE total_procesados INT64 DEFAULT 0;

SET fecha_actual = fecha_inicio;

-- Loop por cada mes
WHILE fecha_actual <= fecha_fin DO
    -- Calcular headcount para este mes
    CALL `pa-prod.pa_gold.sp_calcular_headcount`(fecha_actual, 'pa-prod.pa_gold');
    
    SET total_procesados = total_procesados + 1;
    SET fecha_actual = DATE_ADD(fecha_actual, INTERVAL 1 MONTH);
END WHILE;

SELECT FORMAT("Procesados %d meses de headcount", total_procesados) AS resultado;

-- IF/ELSE con manejo de excepciones
BEGIN
    DECLARE existe BOOL;
    
    SET existe = (
        SELECT COUNT(*) > 0 
        FROM `pa-prod.pa_silver.silver_empleados` 
        WHERE fecha_snapshot = CURRENT_DATE()
    );
    
    IF existe THEN
        CALL `pa-prod.pa_gold.sp_calcular_headcount`(CURRENT_DATE(), 'pa-prod.pa_gold');
    ELSE
        SELECT "No hay datos para hoy. Verificar pipeline de ingesta." AS alerta;
    END IF;

EXCEPTION WHEN ERROR THEN
    SELECT FORMAT("Error: %s", @@error.message) AS error;
END;
```

---

## Recursos adicionales
- [BigQuery best practices](https://cloud.google.com/bigquery/docs/best-practices-performance-overview)
- [Partitioned tables](https://cloud.google.com/bigquery/docs/partitioned-tables)
- [Clustered tables](https://cloud.google.com/bigquery/docs/clustered-tables)
- [INFORMATION_SCHEMA reference](https://cloud.google.com/bigquery/docs/information-schema-intro)
- [Stored Procedures](https://cloud.google.com/bigquery/docs/procedures)
- [UDFs](https://cloud.google.com/bigquery/docs/user-defined-functions)
- [Procedural Language](https://cloud.google.com/bigquery/docs/reference/standard-sql/procedural-language)
