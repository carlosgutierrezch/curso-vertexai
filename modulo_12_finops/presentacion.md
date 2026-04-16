# Módulo 12: Estrategia de FinOps y Control de Costes

## Información de la sesión
- **Sesión:** 9
- **Fecha:** Lunes 8 de Junio, 17:05–17:50
- **Duración:** ~45 minutos (sesión compartida con Módulo 11)
- **Prerequisitos:** Módulos 1–11 completados, acceso a INFORMATION_SCHEMA en BigQuery

---

## Tema 12.1: Modelos de pricing de BigQuery

### Conceptos clave
- BigQuery ofrece dos modelos de pricing fundamentalmente diferentes: **On Demand** (pago por consulta) y **Editions** (capacidad reservada con slots). La elección entre uno y otro puede suponer una diferencia de miles de euros al mes para un equipo de People Analytics.
- El modelo **On Demand** cobra $6.25 por TB de datos procesados (escaneados) por cada consulta. Es sencillo, predecible a nivel de consulta individual, pero puede ser impredecible a nivel mensual si los analistas ejecutan muchas consultas sobre tablas grandes.
- Las **Editions** (Standard, Enterprise, Enterprise Plus) proporcionan capacidad de cómputo medida en **slots** (unidades de procesamiento de BigQuery). Se paga por la capacidad reservada, independientemente de cuántas consultas se ejecuten.

### Detalle técnico

**Comparativa de modelos de pricing (precios orientativos, región EU):**

| Característica | On Demand | Standard Edition | Enterprise Edition | Enterprise Plus |
|---------------|-----------|------------------|--------------------|-----------------|
| **Pricing** | $6.25/TB procesado | Desde $0.04/slot-hora | Desde $0.06/slot-hora | Desde $0.10/slot-hora |
| **Compromiso mínimo** | Ninguno | Ninguno (pay-as-you-go) | 1 año o 3 años | 1 año o 3 años |
| **Slots base** | N/A (2.000 compartidos) | Configurables | Configurables | Configurables |
| **Autoscaler** | N/A | Sí | Sí | Sí |
| **Columnar security** | Sí | Sí | Sí | Sí |
| **Row-level security** | Sí | Sí | Sí | Sí |
| **BI Engine** | Pago separado | Incluido (hasta límite) | Incluido (hasta límite) | Incluido |
| **Streaming** | $0.05/200MB | Incluido | Incluido | Incluido |
| **Caso de uso PA** | Equipos pequeños, < 5 TB/mes | Equipos medianos, predecible | Equipos grandes, SLAs | Enterprise, compliance |

**Cuándo elegir On Demand vs Editions:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    ÁRBOL DE DECISIÓN PRICING                     │
│                                                                  │
│  ¿Cuántos TB procesas al mes?                                   │
│  │                                                               │
│  ├── < 2 TB/mes → ON DEMAND ($12.50/mes aprox.)                │
│  │   Ideal para: equipo PA pequeño, 2-3 analistas,              │
│  │   dashboards con poco volumen                                 │
│  │                                                               │
│  ├── 2-20 TB/mes → EVALUAR                                      │
│  │   Comparar: On Demand ($12.50-$125/mes)                      │
│  │   vs Standard Edition (100 slots = ~$288/mes 24x7)           │
│  │   Clave: ¿los picos son predecibles?                         │
│  │                                                               │
│  └── > 20 TB/mes → EDITIONS                                     │
│      100-200 slots con autoscaler                                │
│      Commitment de 1 año para descuento adicional                │
│      Considerar Enterprise si necesitas features avanzadas       │
│                                                                  │
│  FACTORES ADICIONALES:                                           │
│  - ¿Necesitas BI Engine? → Enterprise incluye créditos           │
│  - ¿Necesitas slots garantizados para SLAs? → Enterprise        │
│  - ¿Presupuesto impredecible? → Editions da control             │
│  - ¿Solo unos pocos usuarios? → On Demand más simple            │
└─────────────────────────────────────────────────────────────────┘
```

**Calcular el coste actual con On Demand:**

```sql
-- Coste estimado On Demand del último mes
SELECT
    ROUND(SUM(total_bytes_billed) / POW(1024, 4), 2) AS tb_billed,
    ROUND(SUM(total_bytes_billed) / POW(1024, 4) * 6.25, 2) AS coste_estimado_usd,
    COUNT(*) AS num_queries
FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
    AND total_bytes_billed > 0;
```

### Aplicación en People Analytics
- Un equipo típico de People Analytics con 5-10 analistas y dashboards en Looker suele procesar entre 3 y 15 TB al mes. En este rango, la decisión entre On Demand y Standard Edition depende de la variabilidad: si el consumo es estable, Editions puede ser más económico; si es muy variable (picos en cierres de trimestre), On Demand puede ser más flexible.
- **Consejo práctico:** Empezar con On Demand, medir durante 3 meses con INFORMATION_SCHEMA, y luego evaluar si merece la pena pasar a Editions.

---

## Tema 12.2: Uso de Reservations y gestión de slots

### Conceptos clave
- Los **slots** son las unidades de cómputo de BigQuery. Cada consulta se divide en etapas que se ejecutan en paralelo utilizando slots. Más slots = consultas más rápidas (hasta cierto punto).
- Las **Reservations** permiten asignar slots a proyectos o equipos específicos, garantizando que un equipo no monopolice los recursos de otro.
- El **Autoscaler** ajusta automáticamente el número de slots entre un mínimo (baseline) y un máximo, permitiendo absorber picos de carga sin sobredimensionar.

### Detalle técnico

**Tipos de compromiso de slots:**

| Tipo | Duración | Descuento vs pay-as-you-go | Cancelación |
|------|----------|---------------------------|-------------|
| **Flex (pay-as-you-go)** | Sin compromiso | 0% (precio base) | En cualquier momento |
| **Annual** | 1 año | ~17-20% descuento | Penalización |
| **Three-year** | 3 años | ~30-40% descuento | Penalización |

**Configurar Reservations con autoscaler:**

```sql
-- Paso 1: Crear una reservation con autoscaler
-- (se hace via bq CLI, API o consola)

-- Ver las reservations actuales
SELECT
    reservation_name,
    slot_capacity,
    ignore_idle_slots
FROM `region-eu.INFORMATION_SCHEMA.RESERVATIONS`;

-- Ver las assignments (qué proyecto usa qué reservation)
SELECT
    reservation_name,
    job_type,
    assignee_id,
    assignee_type
FROM `region-eu.INFORMATION_SCHEMA.ASSIGNMENTS`;

-- Ver el uso de slots en tiempo real
SELECT
    reservation_name,
    period_start,
    period_slot_ms,
    ROUND(period_slot_ms / 1000 / 60, 2) AS slot_minutes,
    num_jobs_completed
FROM `region-eu.INFORMATION_SCHEMA.RESERVATIONS_TIMELINE`
WHERE period_start > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
ORDER BY period_start DESC;
```

**Configuración recomendada para un equipo de People Analytics:**

```
┌─────────────────────────────────────────────────────────────┐
│              CONFIGURACIÓN DE SLOTS RECOMENDADA              │
│                                                              │
│  Reservation: "pa-team"                                      │
│  ├── Baseline slots: 50                                      │
│  ├── Max slots (autoscaler): 200                             │
│  ├── Idle slots: compartidos con otros proyectos             │
│  │                                                           │
│  Assignments:                                                │
│  ├── Proyecto: pa-prod → reservation pa-team (QUERY)         │
│  ├── Proyecto: pa-prod → reservation pa-team (PIPELINE)      │
│  └── Proyecto: pa-dev → default (On Demand para desarrollo)  │
│                                                              │
│  Lógica:                                                     │
│  - En horario normal (9:00-18:00): ~50 slots suficientes     │
│  - Ejecución de Dataform (2:00 AM): autoscaler sube a 150   │
│  - Cierre trimestral (dashboards intensivos): hasta 200      │
│  - Desarrollo (pa-dev): On Demand (bajo volumen, flexible)   │
└─────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- Si el pipeline de Dataform se ejecuta a las 2:00 AM y procesa muchas transformaciones, el autoscaler escala los slots automáticamente durante ese período y los reduce después, optimizando el coste.
- **Separar desarrollo de producción:** El proyecto `pa-dev` debería usar On Demand (los analistas ejecutan consultas ad-hoc de bajo volumen) mientras que `pa-prod` usa Editions con Reservations (dashboards, pipelines, cargas predecibles).
- Los slots ociosos (idle) se pueden compartir con otros proyectos de la organización, maximizando la utilización de la inversión.

---

## Tema 12.3: Análisis de costes mediante INFORMATION_SCHEMA

### Conceptos clave
- `INFORMATION_SCHEMA` es la fuente más rica de metadatos de BigQuery: contiene información sobre consultas ejecutadas, almacenamiento, streaming, reservations y más.
- Las vistas más relevantes para FinOps son: `JOBS_BY_PROJECT` (historial de consultas y su consumo), `TABLE_STORAGE` (tamaño de tablas y eficiencia de almacenamiento) y `STREAMING_TIMELINE` (ingesta en streaming).
- Estas vistas permiten construir dashboards de costes internos sin necesidad de herramientas externas, proporcionando visibilidad completa del gasto del equipo.

### Detalle técnico

**Dashboard de costes por usuario y dataset:**

```sql
-- 1. Coste por usuario (On Demand) en los últimos 30 días
SELECT
    user_email,
    COUNT(*) AS total_queries,
    ROUND(SUM(total_bytes_billed) / POW(1024, 4), 4) AS tb_billed,
    ROUND(SUM(total_bytes_billed) / POW(1024, 4) * 6.25, 2) AS coste_usd,
    ROUND(AVG(total_bytes_billed) / POW(1024, 3), 2) AS avg_gb_por_query,
    ROUND(AVG(total_slot_ms) / 1000, 2) AS avg_slot_seconds,
    COUNTIF(cache_hit) AS queries_cached,
    ROUND(SAFE_DIVIDE(COUNTIF(cache_hit), COUNT(*)) * 100, 1) AS pct_cache_hit
FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
GROUP BY user_email
ORDER BY coste_usd DESC;

-- 2. Coste por dataset referenciado
SELECT
    SPLIT(ref.table_id, '.')[SAFE_OFFSET(0)] AS proyecto,
    SPLIT(ref.table_id, '.')[SAFE_OFFSET(1)] AS dataset,
    COUNT(DISTINCT j.job_id) AS num_queries,
    ROUND(SUM(j.total_bytes_billed) / POW(1024, 4), 4) AS tb_billed,
    ROUND(SUM(j.total_bytes_billed) / POW(1024, 4) * 6.25, 2) AS coste_usd
FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT` j,
    UNNEST(referenced_tables) AS ref
WHERE j.creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND j.job_type = 'QUERY'
    AND j.state = 'DONE'
GROUP BY proyecto, dataset
ORDER BY coste_usd DESC;

-- 3. Consultas más caras del mes
SELECT
    user_email,
    job_id,
    creation_time,
    ROUND(total_bytes_billed / POW(1024, 4), 6) AS tb_billed,
    ROUND(total_bytes_billed / POW(1024, 4) * 6.25, 4) AS coste_usd,
    ROUND(total_slot_ms / 1000, 2) AS slot_seconds,
    SUBSTR(query, 1, 200) AS query_preview
FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
    AND total_bytes_billed > 0
ORDER BY total_bytes_billed DESC
LIMIT 20;

-- 4. Evolución diaria de costes
SELECT
    DATE(creation_time) AS fecha,
    COUNT(*) AS num_queries,
    ROUND(SUM(total_bytes_billed) / POW(1024, 4), 4) AS tb_billed,
    ROUND(SUM(total_bytes_billed) / POW(1024, 4) * 6.25, 2) AS coste_diario_usd,
    COUNT(DISTINCT user_email) AS usuarios_activos
FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
GROUP BY fecha
ORDER BY fecha;
```

**Análisis de almacenamiento:**

```sql
-- 5. Tamaño de tablas y coste de almacenamiento
SELECT
    table_schema AS dataset,
    table_name,
    ROUND(total_logical_bytes / POW(1024, 3), 2) AS logical_gb,
    ROUND(total_physical_bytes / POW(1024, 3), 2) AS physical_gb,
    ROUND(SAFE_DIVIDE(total_physical_bytes, total_logical_bytes), 2) AS compression_ratio,
    ROUND(active_logical_bytes / POW(1024, 3), 2) AS active_gb,
    ROUND(long_term_logical_bytes / POW(1024, 3), 2) AS long_term_gb,
    -- Coste estimado mensual (pricing lógico: $0.02/GB activo, $0.01/GB long-term)
    ROUND(
        (active_logical_bytes / POW(1024, 3) * 0.02) +
        (long_term_logical_bytes / POW(1024, 3) * 0.01),
        4
    ) AS coste_almacenamiento_mensual_usd,
    row_count,
    TIMESTAMP_MILLIS(last_modified_time) AS last_modified
FROM `pa-prod.pa_gold.INFORMATION_SCHEMA.TABLE_STORAGE`
ORDER BY total_logical_bytes DESC;

-- 6. Datasets huérfanos (sin consultas en los últimos 90 días)
WITH tablas_consultadas AS (
    SELECT DISTINCT
        CONCAT(ref.project_id, '.', ref.dataset_id, '.', ref.table_id) AS tabla_completa
    FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT` j,
        UNNEST(referenced_tables) AS ref
    WHERE j.creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
        AND j.job_type = 'QUERY'
)
SELECT
    t.table_schema AS dataset,
    t.table_name,
    ROUND(t.total_logical_bytes / POW(1024, 3), 2) AS logical_gb,
    TIMESTAMP_MILLIS(t.last_modified_time) AS last_modified
FROM `pa-prod.pa_gold.INFORMATION_SCHEMA.TABLE_STORAGE` t
LEFT JOIN tablas_consultadas tc
    ON CONCAT('pa-prod.', t.table_schema, '.', t.table_name) = tc.tabla_completa
WHERE tc.tabla_completa IS NULL
ORDER BY t.total_logical_bytes DESC;
```

### Aplicación en People Analytics
- La consulta de "consultas más caras" suele revelar patrones como: un analista que ejecuta `SELECT *` sobre la tabla completa de empleados en lugar de seleccionar columnas específicas, o un dashboard de Looker que no usa caché y reprocesa los mismos datos cada vez que se abre.
- Las "tablas huérfanas" son comunes en proyectos de PA: tablas de prueba que se crearon durante un análisis exploratorio y nunca se eliminaron. Detectarlas y eliminarlas puede ahorrar dinero en almacenamiento.
- Se recomienda ejecutar estas consultas semanalmente y enviar un resumen al lead del equipo para mantener la conciencia de costes.

---

## Tema 12.4: Integración con APIs de BigQuery y Dataform para control de costes

### Conceptos clave
- El control de costes debe ser **proactivo**, no solo reactivo. Además de analizar el gasto pasado, se pueden implementar controles que prevengan gastos excesivos antes de que ocurran.
- BigQuery permite configurar **cuotas personalizadas** a nivel de proyecto y usuario, y Dataform puede integrar validaciones de coste en el flujo de transformaciones.
- Los controles de costes más efectivos combinan tres capas: prevención (cuotas), detección (alertas) y análisis (dashboards).

### Detalle técnico

**Configurar cuotas de coste por usuario:**

```bash
# Limitar el consumo diario por usuario a 1 TB (equivale a $6.25/día)
bq update --project_id=pa-prod \
  --max_bytes_billed=1099511627776 \
  --default_query_job_timeout_ms=300000

# Para un usuario específico, configurar en la consulta:
# SET @@query_max_bytes_billed = 10737418240; -- 10 GB máximo por consulta
```

**Control de coste integrado en Dataform:**

```sql
-- En Dataform: pre-operation que valida el coste estimado
-- archivo: definitions/gold/fact_rotacion.sqlx

config {
    type: "table",
    schema: "pa_gold",
    description: "Fact table de rotación mensual",
    tags: ["gold", "mensual"]
}

-- Pre-operation: dry run para estimar coste
-- (Se implementa externamente via API, aquí el concepto)
-- La ejecución de Dataform se puede envolver en un script que:
-- 1. Ejecuta cada modelo con --dry_run
-- 2. Suma los bytes estimados
-- 3. Si supera el umbral (ej: 500 GB), alerta y detiene

SELECT
    empleado_id_hash,
    departamento,
    nivel,
    DATE_TRUNC(fecha_baja, MONTH) AS mes_rotacion,
    motivo_baja,
    antigüedad_meses,
    salario_bruto,
    rating_desempeno,
    1 AS rotacion
FROM ${ref("silver_empleados")}
WHERE rotacion = 1
    AND fecha_snapshot = CURRENT_DATE()
```

### Aplicación en People Analytics
- Configurar un **límite de 10 GB por consulta** para analistas junior evita que una consulta mal escrita (sin WHERE, sobre una tabla particionada pero sin filtrar por partición) genere un coste inesperado.
- El pipeline de Dataform debería incluir un paso de validación de coste estimado antes de ejecutar las transformaciones en producción: si el coste estimado del pipeline completo supera un umbral, se detiene y se envía una alerta.

---

## Tema 12.5: Optimización del coste de consultas y almacenamiento

### Conceptos clave
- La optimización de costes en BigQuery se centra en dos ejes: **reducir los bytes procesados** (para On Demand) y **reducir el tiempo de slot** (para Editions).
- Las técnicas más efectivas son: seleccionar solo las columnas necesarias, aprovechar el particionado, usar clustering, materializar vistas intermedias y aprovechar la caché de resultados.
- En almacenamiento, el uso de **long-term storage** (tablas no modificadas en 90+ días) reduce el coste automáticamente a la mitad.

### Detalle técnico

**Técnicas de optimización de consultas:**

| Técnica | Ahorro estimado | Esfuerzo | Ejemplo |
|---------|----------------|----------|---------|
| Evitar `SELECT *` | 50-90% | Bajo | `SELECT col1, col2` en lugar de `SELECT *` |
| Filtrar por partición | 80-99% | Bajo | `WHERE fecha_snapshot = CURRENT_DATE()` |
| Usar clustering | 20-50% | Bajo (al crear tabla) | `CLUSTER BY departamento, nivel` |
| Materializar CTEs repetidos | 30-60% | Medio | Crear tabla intermedia para CTEs usados en múltiples consultas |
| Usar caché de resultados | 100% (gratis) | Ninguno | Activado por defecto, invalidado si la tabla cambia |
| Approximate aggregations | 10-30% | Bajo | `APPROX_COUNT_DISTINCT()` en lugar de `COUNT(DISTINCT)` |
| Evitar JOINs innecesarios | Variable | Medio | Desnormalizar si el JOIN es siempre el mismo |

**Ejemplo de consulta optimizada vs no optimizada:**

```sql
-- ❌ CONSULTA NO OPTIMIZADA (escanea toda la tabla, todas las columnas)
SELECT *
FROM `pa-prod.pa_gold.fact_metricas_mensuales`
WHERE departamento = 'Marketing';
-- Bytes escaneados: ~50 GB (toda la tabla)
-- Coste estimado On Demand: $0.31

-- ✅ CONSULTA OPTIMIZADA (solo columnas necesarias + filtro por partición)
SELECT
    empleado_id_hash,
    departamento,
    headcount,
    tasa_rotacion,
    salario_medio
FROM `pa-prod.pa_gold.fact_metricas_mensuales`
WHERE fecha_mes = '2026-05-01'    -- Filtro por partición
    AND departamento = 'Marketing'; -- Filtro por cluster
-- Bytes escaneados: ~0.5 GB (solo 1 partición, columnas seleccionadas)
-- Coste estimado On Demand: $0.003
-- Ahorro: 99%

-- ✅ USAR MATERIALIZED VIEW para métricas repetidas
CREATE MATERIALIZED VIEW `pa-prod.pa_gold.mv_headcount_mensual`
OPTIONS (
    enable_refresh = true,
    refresh_interval_minutes = 60
)
AS
SELECT
    DATE_TRUNC(fecha_snapshot, MONTH) AS mes,
    departamento,
    nivel,
    COUNT(DISTINCT empleado_id_hash) AS headcount,
    AVG(salario_bruto) AS salario_medio,
    AVG(rating_desempeno) AS rating_medio
FROM `pa-prod.pa_gold.dim_empleado`
GROUP BY mes, departamento, nivel;

-- Las consultas que coincidan con este patrón de agregación
-- se redirigen automáticamente a la materialized view (gratis)
```

**Optimización de almacenamiento:**

```sql
-- Verificar el ratio de long-term storage
SELECT
    table_schema AS dataset,
    SUM(active_logical_bytes) / POW(1024, 3) AS active_gb,
    SUM(long_term_logical_bytes) / POW(1024, 3) AS long_term_gb,
    ROUND(
        SAFE_DIVIDE(
            SUM(long_term_logical_bytes),
            SUM(total_logical_bytes)
        ) * 100, 1
    ) AS pct_long_term,
    -- Ahorro por long-term storage
    ROUND(SUM(long_term_logical_bytes) / POW(1024, 3) * 0.01, 2) AS ahorro_mensual_usd
FROM `pa-prod.INFORMATION_SCHEMA.TABLE_STORAGE`
GROUP BY dataset
ORDER BY active_gb DESC;
```

### Aplicación en People Analytics
- Los dashboards de Looker son la fuente principal de consultas repetidas: si un dashboard se configura con filtros que no aprovechan la partición, cada apertura escanea la tabla completa. Revisar las consultas generadas por Looker (en INFORMATION_SCHEMA) es una de las optimizaciones con mayor impacto.
- Las tablas históricas de People Analytics (historial de headcount, evaluaciones de años anteriores) pasan automáticamente a **long-term storage** después de 90 días sin modificaciones, reduciendo su coste de $0.02/GB a $0.01/GB.
- **Materialized views** son especialmente útiles para métricas que se consultan frecuentemente con los mismos agregados: headcount mensual por departamento, tasa de rotación trimestral, media salarial por nivel.

---

## Tema 12.6: Diferencias entre almacenamiento lógico y físico

### Conceptos clave
- BigQuery ofrece dos modelos de pricing para almacenamiento: **lógico** (basado en el tamaño de los datos sin comprimir) y **físico** (basado en el tamaño comprimido en disco).
- El modelo **físico** suele ser un 60-80% más barato que el lógico para datos tabulares típicos, gracias a la compresión columnar que aplica BigQuery internamente.
- Sin embargo, el modelo físico incluye el coste del **time travel storage** y el **fail-safe storage**, que en tablas con muchas actualizaciones puede ser significativo.

### Detalle técnico

**Comparativa lógico vs físico:**

| Aspecto | Modelo lógico | Modelo físico |
|---------|---------------|---------------|
| **Precio activo** | $0.02/GB/mes | $0.04/GB/mes |
| **Precio long-term** | $0.01/GB/mes | $0.02/GB/mes |
| **Compresión** | No aplica (se mide sin comprimir) | Aplica (~60-80% compresión típica) |
| **Time travel storage** | No se cobra extra | Se cobra al mismo precio |
| **Fail-safe storage** | No se cobra extra | Se cobra al mismo precio |
| **Mejor para** | Tablas con muchas actualizaciones | Tablas estáticas o append-only |

**Calcular qué modelo es más barato para cada tabla:**

```sql
-- Comparar coste lógico vs físico por tabla
SELECT
    table_schema AS dataset,
    table_name,
    ROUND(total_logical_bytes / POW(1024, 3), 2) AS logical_gb,
    ROUND(total_physical_bytes / POW(1024, 3), 2) AS physical_gb,
    ROUND(SAFE_DIVIDE(total_physical_bytes, total_logical_bytes), 2) AS compression_ratio,

    -- Time travel y fail-safe (solo relevante en modelo físico)
    ROUND(time_travel_physical_bytes / POW(1024, 3), 2) AS time_travel_gb,
    ROUND(fail_safe_physical_bytes / POW(1024, 3), 2) AS fail_safe_gb,

    -- Coste mensual estimado con modelo LÓGICO
    ROUND(
        (active_logical_bytes / POW(1024, 3) * 0.02) +
        (long_term_logical_bytes / POW(1024, 3) * 0.01),
        4
    ) AS coste_logico_usd,

    -- Coste mensual estimado con modelo FÍSICO (incluye time travel + fail-safe)
    ROUND(
        ((active_physical_bytes + time_travel_physical_bytes + fail_safe_physical_bytes) / POW(1024, 3) * 0.04) +
        (long_term_physical_bytes / POW(1024, 3) * 0.02),
        4
    ) AS coste_fisico_usd,

    -- ¿Cuál es más barato?
    CASE
        WHEN (active_logical_bytes * 0.02 + long_term_logical_bytes * 0.01) <
             ((active_physical_bytes + time_travel_physical_bytes + fail_safe_physical_bytes) * 0.04 +
              long_term_physical_bytes * 0.02)
        THEN 'LÓGICO más barato'
        ELSE 'FÍSICO más barato'
    END AS modelo_recomendado

FROM `pa-prod.INFORMATION_SCHEMA.TABLE_STORAGE`
WHERE total_logical_bytes > 0
ORDER BY total_logical_bytes DESC;
```

### Aplicación en People Analytics
- Las tablas de tipo **append-only** (como `fact_metricas_mensuales` donde cada mes se añaden filas y nunca se modifican) se benefician enormemente del modelo físico: alta compresión y poco time travel storage.
- Las tablas con **actualizaciones frecuentes** (como `dim_empleado` que se refresca diariamente con DELETE + INSERT) acumulan time travel storage que encarece el modelo físico. Para estas tablas, el modelo lógico puede ser más económico.
- **Recomendación:** Calcular el coste de ambos modelos con la consulta anterior y cambiar a nivel de dataset según el tipo predominante de tablas.

---

## Tema 12.7: Uso de BI Engine para acelerar dashboards

### Conceptos clave
- **BI Engine** es una capa de aceleración en memoria de BigQuery que almacena en caché los datos más consultados, reduciendo drásticamente la latencia de las consultas de dashboards (de segundos a milisegundos).
- BI Engine se integra nativamente con Looker, Looker Studio y Connected Sheets, acelerando las consultas sin necesidad de cambiar el código SQL.
- Se configura mediante una **reservación de memoria** a nivel de proyecto, con un coste de $0.0416/GB/hora (o incluido parcialmente en Editions).

### Detalle técnico

**Configuración y monitorización de BI Engine:**

```sql
-- Ver la capacidad de BI Engine reservada
SELECT
    project_id,
    bi_engine_mode,
    bi_engine_reasons
FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
    AND bi_engine_statistics IS NOT NULL
LIMIT 10;

-- Métricas de uso de BI Engine
-- (se consultan via Cloud Monitoring API o consola)
-- Métricas clave:
-- - bigquery.googleapis.com/bi_engine/memory/capacity_bytes
-- - bigquery.googleapis.com/bi_engine/memory/used_bytes
-- - bigquery.googleapis.com/bi_engine/query/acceleration_mode
```

**Dimensionamiento de BI Engine para People Analytics:**

| Tipo de dashboard | Tablas aceleradas | Memoria necesaria | Latencia sin BI Engine | Latencia con BI Engine |
|-------------------|-------------------|-------------------|----------------------|----------------------|
| Dashboard de headcount | `mv_headcount_mensual` | ~50 MB | 2-5 seg | 100-300 ms |
| Dashboard de rotación | `fact_rotacion`, `dim_empleado` | ~200 MB | 5-15 seg | 200-500 ms |
| Dashboard de equidad salarial | `v_salarios_por_grupo` | ~100 MB | 3-8 seg | 100-400 ms |
| **Total recomendado** | | **~500 MB** | | |

### Aplicación en People Analytics
- Los dashboards de People Analytics en Looker suelen tener un patrón de uso muy predecible: se abren durante las reuniones del comité de dirección (lunes por la mañana) y durante los ciclos de revisión de talento (2-3 semanas al año). BI Engine garantiza que estos momentos críticos tengan respuesta instantánea.
- **Coste-beneficio:** 500 MB de BI Engine cuestan ~$15/mes, pero eliminan la latencia en los dashboards más utilizados. Es una de las inversiones con mejor ROI en la plataforma de datos.
- BI Engine funciona mejor con **materialized views** y tablas agregadas: acelerar una tabla de 10 millones de filas de empleados es menos eficiente que acelerar la vista materializada de métricas mensuales por departamento.

---

## Tema 12.8: Creación de dashboards personalizados de FinOps

### Conceptos clave
- Un dashboard de FinOps proporciona visibilidad continua del gasto en la plataforma de datos, permitiendo identificar tendencias, anomalías y oportunidades de optimización.
- El dashboard debe ser accesible al lead del equipo de datos y, en versión resumida, al responsable de presupuesto de tecnología.
- Las métricas clave son: coste diario/semanal/mensual, coste por usuario, coste por dataset, consultas más caras, ratio de caché, y evolución del almacenamiento.

### Detalle técnico

**Estructura del dashboard de FinOps en Looker Studio:**

```
┌─────────────────────────────────────────────────────────────────┐
│  DASHBOARD FINOPS — PEOPLE ANALYTICS                             │
│  Filtros: [Período ▼] [Usuario ▼] [Dataset ▼]                  │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │ Coste Total  │  │ TB Procesados│  │ Queries      │           │
│  │   $127.45    │  │    20.4 TB   │  │   12,847     │           │
│  │  ▲ +12% MoM  │  │  ▲ +8% MoM  │  │  ▼ -3% MoM  │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
│                                                                  │
│  ┌────────────────────────────────────────────────┐              │
│  │ Evolución diaria de costes (gráfico de líneas) │              │
│  │ ████████████████████████████████████████████    │              │
│  └────────────────────────────────────────────────┘              │
│                                                                  │
│  ┌───────────────────────┐  ┌────────────────────────────┐      │
│  │ Top 5 usuarios        │  │ Top 5 consultas más caras  │      │
│  │ por coste             │  │ (últimos 7 días)           │      │
│  │ 1. analyst@  $42.30   │  │ 1. SELECT * FROM fact_...  │      │
│  │ 2. looker@   $31.10   │  │ 2. JOIN sin partición      │      │
│  │ 3. dataform@ $28.60   │  │ 3. EXPORT DATA ...         │      │
│  └───────────────────────┘  └────────────────────────────┘      │
│                                                                  │
│  ┌────────────────────────────────────────────────┐              │
│  │ Almacenamiento por dataset (gráfico de barras) │              │
│  │ pa_gold   ██████████████████  45 GB             │              │
│  │ pa_silver ████████████  28 GB                   │              │
│  │ pa_bronze ██████████████████████  62 GB          │              │
│  └────────────────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────────┘
```

**Consulta base para alimentar el dashboard:**

```sql
-- Vista para el dashboard de FinOps (se refresca diariamente)
CREATE OR REPLACE VIEW `pa-prod.pa_finops.v_costes_diarios` AS
SELECT
    DATE(creation_time) AS fecha,
    user_email,
    CASE
        WHEN REGEXP_CONTAINS(user_email, r'@.*\.iam\.gserviceaccount\.com$')
        THEN 'Service Account'
        ELSE 'Usuario'
    END AS tipo_usuario,
    COUNT(*) AS num_queries,
    COUNTIF(cache_hit) AS queries_cached,
    ROUND(SUM(total_bytes_billed) / POW(1024, 4), 6) AS tb_billed,
    ROUND(SUM(total_bytes_billed) / POW(1024, 4) * 6.25, 4) AS coste_usd,
    ROUND(AVG(total_slot_ms) / 1000, 2) AS avg_slot_seconds,
    ROUND(MAX(total_bytes_billed) / POW(1024, 3), 2) AS max_gb_single_query
FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
GROUP BY fecha, user_email, tipo_usuario;
```

### Aplicación en People Analytics
- El dashboard de FinOps debe revisarse semanalmente en la reunión del equipo de datos. Si el coste sube más de un 20% respecto a la semana anterior, investigar las causas (nueva tabla sin particionar, nuevo dashboard sin optimizar, analista ejecutando exploración masiva).
- Incluir la **service account de Dataform** como usuario separado permite ver cuánto cuesta el pipeline de transformaciones vs. las consultas ad-hoc de los analistas.

---

## Tema 12.9: Detección automática de picos de coste mediante alertas

### Conceptos clave
- Las alertas automáticas son la última línea de defensa del control de costes: detectan picos anómalos en tiempo (casi) real y notifican al responsable antes de que el gasto se descontrole.
- GCP ofrece dos mecanismos: **Cloud Billing Budgets** (alertas basadas en el presupuesto total del proyecto) y **alertas programáticas** (basadas en consultas SQL sobre INFORMATION_SCHEMA).
- La combinación de ambos proporciona cobertura completa: los budgets detectan el gasto global y las alertas SQL detectan comportamientos anómalos específicos.

### Detalle técnico

**Configurar budget con alertas en Cloud Billing:**

```
┌─────────────────────────────────────────────────────────────┐
│              CONFIGURACIÓN DE BUDGET                         │
│                                                              │
│  Budget: "PA - BigQuery Mensual"                             │
│  ├── Monto: $500/mes                                         │
│  ├── Scope: Proyecto pa-prod, servicio BigQuery              │
│  ├── Alertas:                                                │
│  │   ├── 50% ($250) → Email al lead del equipo              │
│  │   ├── 80% ($400) → Email al lead + Slack #pa-alerts      │
│  │   ├── 100% ($500) → Email + Slack + Pub/Sub trigger      │
│  │   └── 120% ($600) → Pub/Sub → Cloud Function que         │
│  │                      deshabilita usuarios no esenciales    │
│  └── Pub/Sub topic: pa-billing-alerts                        │
└─────────────────────────────────────────────────────────────┘
```

**Alerta programática: detectar picos diarios:**

```sql
-- Consulta programada (Cloud Scheduler + scheduled query)
-- Se ejecuta cada día a las 22:00 y envía alerta si el coste
-- del día supera 2x la media de los últimos 30 días

CREATE OR REPLACE TABLE `pa-prod.pa_finops.alerta_pico_diario` AS
WITH media_historica AS (
    SELECT
        ROUND(AVG(coste_diario_usd), 2) AS media_diaria,
        ROUND(STDDEV(coste_diario_usd), 2) AS stddev_diaria
    FROM (
        SELECT
            DATE(creation_time) AS fecha,
            SUM(total_bytes_billed) / POW(1024, 4) * 6.25 AS coste_diario_usd
        FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
        WHERE creation_time BETWEEN
            TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY) AND
            TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
            AND job_type = 'QUERY'
            AND state = 'DONE'
        GROUP BY fecha
    )
),
coste_hoy AS (
    SELECT
        CURRENT_DATE() AS fecha,
        ROUND(SUM(total_bytes_billed) / POW(1024, 4) * 6.25, 2) AS coste_usd
    FROM `region-eu.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
    WHERE DATE(creation_time) = CURRENT_DATE()
        AND job_type = 'QUERY'
        AND state = 'DONE'
)
SELECT
    h.fecha,
    h.coste_usd AS coste_hoy_usd,
    m.media_diaria,
    m.stddev_diaria,
    ROUND(h.coste_usd / NULLIF(m.media_diaria, 0), 2) AS ratio_vs_media,
    CASE
        WHEN h.coste_usd > m.media_diaria + (2 * m.stddev_diaria) THEN 'ALERTA_CRITICA'
        WHEN h.coste_usd > m.media_diaria * 1.5 THEN 'ALERTA_WARNING'
        ELSE 'NORMAL'
    END AS estado
FROM coste_hoy h
CROSS JOIN media_historica m;

-- Si el estado es ALERTA_CRITICA, enviar notificación via Cloud Function
-- que lee esta tabla y envía a Slack/email
```

**Resumen de controles FinOps implementados:**

```
┌────────────────────────────────────────────────────────────────┐
│               STACK COMPLETO DE FINOPS                          │
│                                                                  │
│  PREVENCIÓN                                                      │
│  ├── Cuotas por usuario (max_bytes_billed)                      │
│  ├── Timeout de consultas (query_timeout_ms)                    │
│  └── Dry run antes de ejecutar en Dataform                      │
│                                                                  │
│  DETECCIÓN                                                       │
│  ├── Cloud Billing Budgets (50%, 80%, 100%, 120%)               │
│  ├── Scheduled query: picos diarios vs media histórica          │
│  └── Alertas de slots: uso > 90% de la reservation              │
│                                                                  │
│  ANÁLISIS                                                        │
│  ├── Dashboard FinOps en Looker Studio                          │
│  ├── Informe semanal de top queries por coste                   │
│  ├── Informe mensual de almacenamiento por dataset              │
│  └── Revisión trimestral: ¿On Demand o Editions?                │
│                                                                  │
│  OPTIMIZACIÓN CONTINUA                                           │
│  ├── Revisar materialized views mensualmente                    │
│  ├── Eliminar tablas huérfanas trimestralmente                  │
│  ├── Evaluar modelo de almacenamiento (lógico vs físico)        │
│  └── Ajustar reservation slots según uso real                   │
└────────────────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- La alerta más valiosa suele ser la de **consultas individuales caras**: un analista que lanza por error un `SELECT * FROM tabla_historica_completa` genera un pico detectable en minutos. La alerta le notifica y le ayuda a corregir la consulta.
- Los **cierres de trimestre** son períodos de alto consumo predecible en People Analytics (revisiones de talento, informes de retribución). Se puede configurar un presupuesto temporal más alto para esos períodos.
- **Cultura de coste:** Incluir el coste estimado de cada consulta en los comentarios de los notebooks y dashboards ayuda a que los analistas sean conscientes del impacto económico de sus decisiones técnicas.

---

## Resumen del módulo

```
┌────────────────────────────────────────────────────────────────┐
│              FINOPS — CONTROLES IMPLEMENTADOS                    │
│                                                                  │
│  PRICING         │  ANÁLISIS            │  OPTIMIZACIÓN          │
│  ────────        │  ────────            │  ────────────          │
│  On Demand vs    │  INFORMATION_SCHEMA  │  Evitar SELECT *       │
│  Editions        │  Coste por usuario   │  Partición + cluster   │
│  Reservations    │  Coste por dataset   │  Materialized views    │
│  Autoscaler      │  Queries más caras   │  BI Engine             │
│                  │  Almacenamiento      │  Long-term storage     │
│                  │                      │  Lógico vs físico      │
│                                                                  │
│  ALERTAS:                                                        │
│  Cloud Billing Budgets + Scheduled queries + Pub/Sub triggers    │
└────────────────────────────────────────────────────────────────┘
```

---

## Próximo módulo

**Módulo 13: Uso Profesional de Google Sheets desde BigQuery** — Pasamos a la capa de consumo, donde los stakeholders de RRHH acceden a datos desde Google Sheets de forma segura y controlada.
