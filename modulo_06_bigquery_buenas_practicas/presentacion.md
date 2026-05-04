# Módulo 6: Buenas Prácticas de BigQuery para Ingenieros de Datos

## Información de la sesión
- **Sesión:** 3 (segunda parte — se imparte junto con el Módulo 5)
- **Fecha:** Lunes 4 de Mayo, 2026, 16:00–18:00
- **Tiempo asignado al Módulo 6:** ~70 minutos (temas 6.1–6.11 en vivo)
- **Audiencia:** Ingenieros y analistas de datos avanzados (equipo de People Analytics)
- **Prerequisitos:** Módulos 1–4 completados. Datasets `bronze_personio` / `silver_personio` / `gold_people_analytics` poblados con datos reales anonimizados de Personio. Bucket `*-datalake` con la zona Bronze.
- **Estructura de la sesión:** Repaso → Módulo 5 → Módulo 6 (proyecto e2e) → Test de Conceptos → Feedback Individual
- **Notebook práctico:** Módulo 6 notebook — **proyecto end-to-end de Retention Risk Pipeline** estilo *procurement template*. 13 secciones que cubren todos los temas de M6 aplicados a un caso real de People Analytics.

### Temas en vivo (Sesión 3, parte 2):
| Tema  | Contenido | Tiempo |
|-------|-----------|--------|
| 6.1  | Modelado de datasets de producción | 7 min |
| 6.2  | Particionamiento y clustering | 8 min |
| 6.3  | Control de coste por consulta | 7 min |
| 6.4  | Optimización de rendimiento | 6 min |
| 6.5  | Permisos a nivel dataset y tabla | 6 min |
| 6.6  | Tablas intermedias y capa semántica | 6 min |
| 6.7  | Versionado de tablas | 5 min |
| 6.8  | Datos históricos y snapshots | 5 min |
| 6.9  | Documentación técnica de modelos | 5 min |
| 6.10 | Auditoría de queries con INFORMATION_SCHEMA | 7 min |
| 6.11 | Stored Procedures, UDFs y Procedural Language | 8 min |

---

## Filosofía del módulo

> "BigQuery no es una base de datos — es un motor analítico distribuido. Las decisiones que se toleran en Postgres (sin índices, sin particiones, JOINs sin filtro) se traducen aquí a *euros* facturados al cliente."

En People Analytics el coste no es solo monetario:
- Una query mal escrita sobre `silver_personio.fact_payroll_monthly` puede leer **datos sensibles** (salarios, bonus) que no necesitabas.
- Un dashboard sin capa semántica acaba con cada analista calculando el *headcount* de forma distinta → reuniones de 45 minutos discutiendo qué número es "el bueno".
- Sin auditoría de queries, no sabes quién accedió a la nómina ni cuánto costó esa exploración.

El proyecto e2e del notebook es un **pipeline de Retention Risk** mensual: cada fin de mes se construye un *feature store*, se entrena un modelo BQML, se aplica una regla de decisión newsvendor (Cu vs Co) y se publica una lista priorizada para HRBP. Es realista, sensible (es un modelo que afecta a personas) y nos obliga a aplicar **todos** los temas de M6 a la vez.

---

## Tema 6.1: Modelado de datasets de producción

### Conceptos clave
- En BigQuery, un **dataset** no es una "base de datos lógica" cualquiera — es la unidad mínima de **gobierno** (permisos, ubicación geográfica, política de retención, labels de coste).
- El estándar de capas medallion (Bronze → Silver → Gold) que vimos en M2 es solo el comienzo: en producción aparecen capas adicionales (`feature_store`, `predictions`, `audit`, `pipeline_runs`).
- El nombre del dataset debe codificar **dominio + capa + entorno**: `people_analytics_gold_prod`, no `gold` a secas.

### Detalle técnico

**Topología de datasets recomendada para People Analytics en producción:**

```
proyecto: people-analytics-formacion
├── bronze_personio                ← datos crudos, sin transformar
├── silver_personio                ← limpio, tipado, dimensional
├── gold_people_analytics          ← métricas de negocio, vistas autorizadas
├── feature_store_retention        ← features ML versionadas, particionadas
├── predictions_retention          ← outputs de modelos (scores, decisiones)
├── ml_models                      ← modelos BQML (logistic, AutoML imports)
├── pipeline_runs                  ← logs de ejecución, lineage, métricas de coste
└── sandbox_<usuario>              ← exploración personal (TTL 7 días)
```

**Decisiones de modelado relevantes en cada capa:**

| Capa | Granularidad | Particionado | Clustering | Retención | Permisos |
|------|--------------|--------------|------------|-----------|----------|
| Bronze | Snapshot de la fuente | Por fecha de carga | Ninguno | 90 días | Solo SAs de ingesta |
| Silver | Transaccional / dimensional | Por fecha de evento (`effective_date`) | `country, band` | 7 años (legal) | SAs de transformación |
| Gold | Métricas agregadas | Por mes (`snapshot_month`) | `country, cohort` | 5 años | Analistas + dashboards |
| Feature store | Una fila por (entidad × snapshot) | Por `snapshot_month` | `country, band` | 2 años | Equipo ML únicamente |
| Predictions | Una fila por (entidad × run) | Por `run_date` | `model_version, cohort` | 1 año | HRBP (vistas autorizadas) |

### Aplicación en People Analytics
- **Caso real:** la tabla `silver_personio.fact_payroll_monthly` contiene salario detallado por empleado-mes. Si la dejamos en el dataset `silver_personio` con permisos amplios, cualquier analista podría hacer `SELECT employee_id, gross_salary FROM ...`. Mejor: dejarla en silver con permisos restringidos a SAs de transformación, y exponer agregados en `gold_people_analytics` a nivel de cohorte.
- **Anti-patrón frecuente:** crear `dataset_temp_jorge_2025`, dejarlo lleno de tablas sin documentar y abandonarlo. Soluciones: (1) datasets `sandbox_<usuario>` con TTL configurado en `default_table_expiration_ms`; (2) revisión trimestral de datasets sin actividad.

---

## Tema 6.2: Particionamiento y clustering

### Conceptos clave
- **Particionado:** divide físicamente la tabla en bloques por una columna (típicamente fecha). BigQuery solo lee los bloques que el `WHERE` exige → **menos bytes facturados**.
- **Clustering:** ordena físicamente los datos dentro de cada partición por hasta 4 columnas. No reduce el escaneo total pero acelera filtros y JOINs frecuentes.
- Regla pragmática: **si la tabla supera los 1 GB y tiene una columna de fecha o cohorte → particiona y clusteriza**. Por debajo no compensa la complejidad.

### Detalle técnico

**Tipos de particionado en BigQuery:**

| Tipo | Cuándo usarlo | Ejemplo PA |
|------|---------------|------------|
| `DATE` / `TIMESTAMP` (column-based) | Datos con una columna temporal natural | `fact_payroll_monthly` por `payroll_month` |
| `_PARTITIONTIME` (ingestion-time) | Cargas append-only sin columna fecha clara | `bronze_personio.raw_audit_log` |
| `INTEGER` range | IDs con cardinalidad acotada | `fact_employee_engagement` por `survey_id` |

**Ejemplo real (capa Silver):**

```sql
CREATE OR REPLACE TABLE silver_personio.fact_payroll_monthly
PARTITION BY payroll_month
CLUSTER BY country, band
OPTIONS(
  partition_expiration_days = 2555,   -- 7 años (retención legal nómina)
  require_partition_filter = TRUE,    -- obliga a filtrar por partición → previene queries asesinas
  description = "Nómina mensual detallada. Particionada por mes, clusterizada por país y banda. Permisos restringidos a SA de transformación."
);
```

La opción `require_partition_filter = TRUE` es **clave**: una query como `SELECT * FROM fact_payroll_monthly` sin filtro de fecha **fallará** en lugar de leer terabytes. Este es el guardarraíl de coste más efectivo de BigQuery.

**Clustering — ¿qué columnas elegir?**

Reglas de pulgar:
1. **Cardinalidad media-alta** (no `gender` con 2 valores, no `employee_id` con 200K).
2. **Aparece en `WHERE` o `JOIN ON`** en ≥30% de las queries.
3. **Orden importa**: más selectiva primero. `CLUSTER BY country, band` filtra mejor "España + P2" que "P2 + España" (porque `country` aparece más en filtros).

**Cuándo NO particionar:**
- Tablas pequeñas (<100 MB): la sobrecarga de metadatos del particionado supera el ahorro.
- Tablas con escrituras muy frecuentes en muchas particiones simultáneas (BigQuery limita a ~10K modificaciones de partición/día por tabla).

### Aplicación en People Analytics
- **Caso del proyecto:** `feature_store_retention` particionada por `snapshot_month`, clusterizada por `country, band`. El query "dame las features del último mes para España, banda P2" lee solo ~5 MB en lugar de los ~300 MB de la tabla completa.
- **Anti-patrón:** particionar por `gender` o `department`. Cardinalidad demasiado baja, particiones inestables, no aporta nada.

---

## Tema 6.3: Control de coste por consulta

### Conceptos clave
- BigQuery factura por **bytes leídos** en modo *On-demand* (~$5 por TiB en US/EU multi-region). En *Editions* factura por slot-hour reservado.
- Una sola query mal escrita sobre datos de nómina puede costar más que un mes de licencia.
- El control efectivo se hace en **3 capas**: (a) guardarraíles a nivel proyecto/usuario, (b) guardarraíles a nivel tabla, (c) prácticas individuales por query.

### Detalle técnico

**Guardarraíles a nivel proyecto (cuotas):**

```bash
# Cuota: máximo 1 TiB facturado por día por usuario (no por proyecto entero)
gcloud alpha services quota update \
  --service=bigquery.googleapis.com \
  --consumer=projects/people-analytics-formacion \
  --metric=bigquery.googleapis.com/quota/query/usage \
  --unit=1/d/{project}/{user} \
  --value=1099511627776   # 1 TiB en bytes
```

**Guardarraíles a nivel query (Python):**

```python
job_config = bigquery.QueryJobConfig(
    maximum_bytes_billed=10 * 1024**3,  # 10 GiB; si la query lo excede, falla antes de ejecutarse
    labels={
        "team": "people-analytics",
        "pipeline": "retention-risk",
        "env": "prod",
    },
    use_query_cache=True,
)
job = bq_client.query(sql, job_config=job_config)
```

**Dry runs — la herramienta más infrautilizada:**

```python
dry_config = bigquery.QueryJobConfig(dry_run=True, use_query_cache=False)
dry_job = bq_client.query(sql, job_config=dry_config)
print(f"Esta query leería {dry_job.total_bytes_processed / 1024**3:.2f} GiB")
# Si sale algo escandaloso, abortamos antes de pagar.
```

**Cost estimation cell pattern** (que usaremos en el notebook):

| Coste | Bytes leídos | Equivalente |
|-------|--------------|-------------|
| $0.0001 | 20 MB | Una query sobre una partición |
| $0.005 | 1 GB | Tabla Silver completa de una entidad pequeña |
| $0.50 | 100 GB | Auditoría histórica completa |
| $5.00 | 1 TB | Aviso al manager |
| $50+ | 10 TB+ | Aviso al CFO |

### Aplicación en People Analytics
- **Caso real:** un analista hace `SELECT * FROM silver_personio.fact_payroll_monthly` para "ver los datos rápido". Sin `require_partition_filter`, lee 7 años de nómina (~50 GB) y le cuesta al cliente $0.25 — multiplicado por 30 analistas en 200 días laborales = $1,500/año tirados.
- **Patrón correcto:** `LIMIT 100` no reduce los bytes leídos en BigQuery (lee toda la partición igualmente). Para muestreos usa `TABLESAMPLE SYSTEM (1 PERCENT)` o particiones explícitas.

---

## Tema 6.4: Optimización de rendimiento

### Conceptos clave
- "Rendimiento" en BigQuery raramente significa "velocidad de CPU". Significa: **bytes leídos** (cost), **slot-time consumido** (latencia), y **shuffle** (cuánto se mueven datos entre workers).
- El plan de ejecución (`EXPLAIN` o pestaña *Execution Details* en la UI) es el primer sitio donde mirar cuando una query es lenta.

### Detalle técnico

**Las 5 optimizaciones que dan el 80% del valor:**

1. **Filtra antes de hacer JOIN.** Materializa subqueries con `WITH` y aplica `WHERE` dentro. BQ tiene predicate pushdown, pero ser explícito ayuda al optimizer.
2. **Evita `SELECT *`.** Trae solo las columnas que vas a usar — BigQuery es columnar, leer 5 columnas vs 50 cuesta 10× menos.
3. **Usa funciones aproximadas cuando puedas.** `APPROX_COUNT_DISTINCT(employee_id)` consume ~10× menos slots que `COUNT(DISTINCT ...)`.
4. **Reorganiza JOINs por tamaño.** La tabla más grande primero (left), las más pequeñas después. BQ ahora hace broadcast joins automáticamente para tablas <20 MB pero hay que ayudarlo.
5. **`QUALIFY` en lugar de subquery + `WHERE`.** Más legible y a veces más rápido para filtros sobre window functions.

**Ejemplo PA — antes y después:**

```sql
-- ❌ Anti-patrón: ~8 GB leídos
SELECT *
FROM silver_personio.fact_payroll_monthly p
JOIN silver_personio.dim_employee e USING(employee_code)
WHERE EXTRACT(YEAR FROM payroll_month) = 2025
  AND e.country = 'ES';

-- ✅ Optimizado: ~120 MB leídos (66× menos)
WITH payroll_2025_es AS (
  SELECT employee_code, payroll_month, gross_salary, bonus_amount
  FROM silver_personio.fact_payroll_monthly
  WHERE payroll_month BETWEEN '2025-01-01' AND '2025-12-31'   -- partition pruning
),
emp_es AS (
  SELECT employee_code, band, hire_date
  FROM silver_personio.dim_employee
  WHERE country = 'ES'
)
SELECT p.*, e.band, e.hire_date
FROM payroll_2025_es p
JOIN emp_es e USING(employee_code);
```

**Caching:** BQ cachea resultados ~24h si la query es bit-idéntica y los datos subyacentes no cambian. El cache es **gratis** (no se factura). No cuentes con él para tablas que se actualizan continuamente.

### Aplicación en People Analytics
- **Métrica que vigilar:** *slot-ms / bytes processed* — si sube, algo se está volviendo CPU-bound (typical: window functions sin `PARTITION BY` correcto).
- **Trampa típica:** `LEFT JOIN` cuando bastaba `INNER` → BQ procesa nulls innecesariamente.

---

## Tema 6.5: Permisos a nivel dataset y tabla

### Conceptos clave
- BigQuery soporta IAM en 4 niveles: **proyecto > dataset > tabla > columna/fila**.
- En People Analytics, el principio de mínimo privilegio se aplica con dolor: HR quiere "ver todos los empleados", pero "todos" incluye salarios, datos médicos, evaluaciones de desempeño.
- **Authorized views** y **Authorized routines** son el patrón para "dejar consultar agregados sin dar acceso a la tabla base".

### Detalle técnico

**Roles BigQuery más relevantes:**

| Rol | Qué permite | Cuándo asignarlo en PA |
|-----|-------------|------------------------|
| `roles/bigquery.dataViewer` | Leer tablas y vistas | Analistas a `gold_people_analytics` |
| `roles/bigquery.dataEditor` | Crear/modificar tablas | SAs de pipeline |
| `roles/bigquery.dataOwner` | Lo anterior + IAM | Solo data engineers senior |
| `roles/bigquery.jobUser` | Lanzar queries | Cualquiera que use el data warehouse |
| `roles/bigquery.metadataViewer` | Ver schemas pero NO datos | Auditores |

**Authorized view — el patrón clave:**

```sql
-- Vista en gold que oculta el salario individual y solo expone agregados
CREATE OR REPLACE VIEW gold_people_analytics.v_compa_ratio_by_cohort AS
SELECT
  country,
  band,
  COUNT(*) AS headcount,
  AVG(SAFE_DIVIDE(gross_salary, band_midpoint)) AS avg_compa_ratio,
  APPROX_QUANTILES(SAFE_DIVIDE(gross_salary, band_midpoint), 100)[OFFSET(50)] AS median_compa_ratio
FROM silver_personio.fact_payroll_monthly p
JOIN silver_personio.dim_employee e USING(employee_code)
WHERE payroll_month = (SELECT MAX(payroll_month) FROM silver_personio.fact_payroll_monthly)
GROUP BY country, band
HAVING COUNT(*) >= 5;   -- k-anonymity: nunca cohortes de menos de 5
```

```python
# Autorizar la vista para que pueda leer la tabla base sin que el usuario tenga acceso directo
view_id = "people-analytics-formacion.gold_people_analytics.v_compa_ratio_by_cohort"
source = bq_client.get_dataset("silver_personio")
source.access_entries.append(bigquery.AccessEntry(role=None, entity_type="view", entity_id={
    "projectId": "people-analytics-formacion",
    "datasetId": "gold_people_analytics",
    "tableId": "v_compa_ratio_by_cohort",
}))
bq_client.update_dataset(source, ["access_entries"])
```

**Column-level security (BigQuery Policy Tags):**

Para datos como `gross_salary`, `iban`, `national_id`: crear una taxonomía en Data Catalog, etiquetar columnas, y conceder permisos por tag (no por columna individual). Lo veremos a fondo en M11 (Cloud DLP) — aquí solo se siembra el concepto.

### Aplicación en People Analytics
- **Caso del cliente:** `silver_personio.dim_employee` tiene `iban` y `national_id` (anonimizados en el export, pero en producción reales). Solución: política de tag `pii_high_sensitivity` en esas columnas, solo desbloqueables por SA de nómina.
- **Anti-patrón:** dar `roles/bigquery.dataViewer` sobre `silver_personio` "para que los analistas exploren". Te van a leer salarios.

---

## Tema 6.6: Tablas intermedias y capa semántica

### Conceptos clave
- "Capa semántica" = el conjunto de **vistas y tablas** que define **una sola versión** de cada métrica de negocio (headcount, FTE, attrition, compa-ratio).
- Sin capa semántica, cada analista calcula "headcount" de forma sutilmente distinta → inconsistencia → desconfianza en el dato.
- Las **tablas intermedias** (materializadas) sirven para precomputar joins/agregaciones caras y reutilizarlas en múltiples vistas downstream.

### Detalle técnico

**Patrón de capa semántica en 3 niveles:**

```
silver_personio.fact_*              ← datos transaccionales
        │
        ├─ tabla intermedia: gold_people_analytics.headcount_monthly (materializada, 1 fila/mes/cohorte)
        │
        ├─ vista semántica: gold_people_analytics.v_headcount  (define LA fórmula oficial)
        │
        └─ vista por dominio: gold_people_analytics.v_dashboard_director_es  (filtrada para un consumidor)
```

**Definir "headcount" de forma oficial:**

```sql
-- Tabla intermedia (refrescada por SP mensual)
CREATE OR REPLACE TABLE gold_people_analytics.headcount_monthly
PARTITION BY snapshot_month
CLUSTER BY country, band
OPTIONS(description = "Headcount oficial: empleados activos al último día del mes (FTE ponderado).") AS
SELECT
  DATE_TRUNC(snapshot_date, MONTH) AS snapshot_month,
  country, band,
  COUNT(DISTINCT employee_code) AS headcount_persons,
  SUM(fte) AS headcount_fte
FROM silver_personio.fact_employee_history
WHERE status = 'active'
  AND snapshot_date = LAST_DAY(snapshot_date, MONTH)
GROUP BY snapshot_month, country, band;
```

**Materialized views vs tablas:**

| Aspecto | View | Materialized View | Tabla intermedia (manual) |
|---------|------|-------------------|---------------------------|
| Coste de query | Recalcula cada vez | Cache automático, refresco incremental | Solo lee |
| Coste de almacenamiento | 0 | Bajo | Alto |
| Frescura | Tiempo real | Casi tiempo real | Depende del SP |
| Soporta UDFs/SP | Sí | Limitado | Sí |
| Casos PA | Lookup ligero | Métricas frecuentes simples | Métricas con lógica de negocio compleja |

### Aplicación en People Analytics
- **Caso del proyecto:** tendremos `feature_store_retention` (tabla intermedia, refrescada mensualmente por SP) → `v_retention_risk_dashboard` (vista semántica) → consumida por Looker Studio en M14.
- **Beneficio cuantificable:** un dashboard con 12 widgets que usen `v_headcount` lee la tabla intermedia 12 veces (~50 MB total) en lugar de recomputar los joins desde Silver (~3 GB × 12 = 36 GB). Ahorro: 99%.

---

## Tema 6.7: Versionado de tablas

### Conceptos clave
- BigQuery no tiene "ramas" como Git. El versionado se hace a través de: (a) **time travel** (recuperar estado pasado hasta 7 días), (b) **table snapshots** (copias zero-cost congeladas), (c) **convención de naming** (`tabla_v2`, `tabla_v3` cuando el schema cambia incompatiblemente).
- En People Analytics, versionar matter porque: una métrica recalculada con nueva fórmula no debe sobrescribir silenciosamente la vieja — los dashboards históricos del CHRO se romperían.

### Detalle técnico

**Estrategia de versionado por tipo de cambio:**

| Cambio | Estrategia | Ejemplo |
|--------|------------|---------|
| Añadir columna nullable | In-place (`ALTER TABLE ADD COLUMN`) | Añadir `engagement_score` a `dim_employee` |
| Cambiar tipo de columna | Crear `_v2`, migrar, deprecar | `salary` de STRING a NUMERIC |
| Cambiar lógica de métrica | Crear vista `_v2`, mantener `_v1` 6 meses | Nueva fórmula de FTE ponderado |
| Cambiar particionado | Crear nueva tabla, swap atómico | De ingestion-time a column-based |

**Time travel (los últimos 7 días):**

```sql
-- ¿Cómo estaba la tabla hace 2 horas, antes del DELETE accidental?
SELECT *
FROM silver_personio.dim_employee
  FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR);

-- Recuperar la tabla completa
CREATE OR REPLACE TABLE silver_personio.dim_employee_recovered AS
SELECT *
FROM silver_personio.dim_employee
  FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR);
```

**Snapshots (sin coste de almacenamiento si no diverge la base):**

```sql
-- Snapshot diario auditable, retenido 1 año
CREATE SNAPSHOT TABLE silver_personio.dim_employee_snapshot_20260430
CLONE silver_personio.dim_employee
OPTIONS(
  expiration_timestamp = TIMESTAMP("2027-04-30 00:00:00 UTC"),
  description = "Snapshot del 30 de abril 2026 — pre-revisión salarial Q2"
);
```

### Aplicación en People Analytics
- **Caso del proyecto:** antes de cada ejecución del pipeline mensual de retention, tomamos snapshot de `feature_store_retention` y `predictions_retention`. Si después se descubre un bug en el modelo, podemos auditar exactamente qué scores se dieron en ese momento.
- **Buena práctica:** automatizar snapshots desde el SP del pipeline (los crearemos en el notebook).

---

## Tema 6.8: Datos históricos y snapshots

### Conceptos clave
- "Datos históricos" en PA tiene dos significados que se confunden constantemente:
  1. **Histórico transaccional**: cada cambio en una entidad genera una fila nueva (ascensos, cambios salariales, cambios de país). Modelado por **SCD Tipo 2**.
  2. **Histórico de snapshots**: el estado completo de la entidad en un instante. Modelado como **fact table de snapshots periódicos**.
- Las dos coexisten. SCD2 te dice "cuándo cambió Juan de banda P2 a P3"; los snapshots mensuales te dicen "cuántos empleados había el 31 de enero".

### Detalle técnico

**SCD Tipo 2 — la implementación correcta en BigQuery:**

```sql
CREATE OR REPLACE TABLE silver_personio.dim_employee_scd2 (
  employee_code STRING NOT NULL,
  country STRING,
  band STRING,
  manager_code STRING,
  effective_from DATE NOT NULL,
  effective_to DATE,                    -- NULL si es la versión actual
  is_current BOOL NOT NULL
)
PARTITION BY effective_from
CLUSTER BY employee_code, is_current;

-- MERGE patrón para nuevo dato
MERGE silver_personio.dim_employee_scd2 t
USING (
  SELECT employee_code, country, band, manager_code, CURRENT_DATE() AS effective_from
  FROM staging.dim_employee_new
) s
ON t.employee_code = s.employee_code AND t.is_current = TRUE
WHEN MATCHED AND (t.country != s.country OR t.band != s.band OR t.manager_code != s.manager_code) THEN
  UPDATE SET effective_to = s.effective_from, is_current = FALSE
WHEN NOT MATCHED THEN
  INSERT (employee_code, country, band, manager_code, effective_from, effective_to, is_current)
  VALUES (s.employee_code, s.country, s.band, s.manager_code, s.effective_from, NULL, TRUE);
```

(Lo profundizaremos en M8 con Dataform — aquí solo el patrón.)

**Snapshots periódicos — patrón para `fact_employee_history`:**

```sql
-- Una fila por (empleado × último día de mes)
CREATE OR REPLACE TABLE silver_personio.fact_employee_history
PARTITION BY snapshot_date
CLUSTER BY country, band AS
SELECT
  LAST_DAY(payroll_month, MONTH) AS snapshot_date,
  e.employee_code, e.country, e.band, e.fte, e.status,
  p.gross_salary, p.bonus_amount
FROM silver_personio.dim_employee e
JOIN silver_personio.fact_payroll_monthly p USING(employee_code)
WHERE e.is_current = TRUE OR e.effective_to >= LAST_DAY(payroll_month, MONTH);
```

### Aplicación en People Analytics
- **Caso del cliente:** la tabla `personio_history_v2_anon.csv` es exactamente esto — snapshots mensuales con `hc_status` (ALTA/BAJA), `status` (active/inactive), `exit_type`. Es nuestra fuente para entrenar el modelo de retención.
- **Trampa común:** confundir "última fila" con "estado actual". Si un empleado se da de baja en marzo y vuelve en septiembre, hay 2 filas con `hc_status = 'ALTA'` separadas por una de `'BAJA'`. El modelo debe respetar esa secuencia.

---

## Tema 6.9: Documentación técnica de modelos

### Conceptos clave
- "Documentación" en BigQuery no es solo un Confluence — son **metadatos vivos** que se almacenan junto al objeto: descripciones de tabla, descripciones de columna, labels.
- Cuando un analista nuevo entra al proyecto, **debe poder entender el modelo solo navegando por la consola de BigQuery**, sin pedirle nada al equipo de datos.

### Detalle técnico

**Niveles de documentación obligatoria:**

| Nivel | Qué se documenta | Dónde |
|-------|------------------|-------|
| Dataset | Propósito, owner, retención, contacto | `description` del dataset + labels |
| Tabla | Granularidad, fuente, frecuencia de refresco, particionado/clustering | `description` + labels |
| Columna | Significado, dominio, fuente, transformaciones | `description` por campo |
| Vista | Lógica de negocio, dependencias, casos de uso | Comentario `--` al inicio + `description` |
| Stored Proc | Inputs/outputs, idempotencia, side effects | Comentario `/** ... */` + entry en `pipeline_runs` |

**Ejemplo aplicado a `feature_store_retention`:**

```sql
ALTER TABLE feature_store_retention.features
SET OPTIONS(
  description = "Feature store mensual para el modelo de retention risk. "
                "Granularidad: 1 fila por (employee_code, snapshot_month). "
                "Refrescada por sp_build_retention_features el día 1 de cada mes. "
                "Owner: data-eng-team@. Retención: 24 meses."
);

ALTER TABLE feature_store_retention.features
ALTER COLUMN compa_ratio
SET OPTIONS(
  description = "Salario base / midpoint de la banda. <0.85 = underpaid, >1.15 = overpaid. "
                "Fuente: SAFE_DIVIDE(p.gross_salary, b.midpoint). NULL si banda no está mapeada."
);

ALTER TABLE feature_store_retention.features
SET OPTIONS(labels = [("team", "people-analytics"), ("contains_pii", "false"), ("env", "prod")]);
```

**Labels — el sistema de tagging para FinOps:**

```python
# Labels nos permitirán en M12 hacer FROM `region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
# WHERE labels.team = 'people-analytics' GROUP BY labels.pipeline → coste por pipeline
LABELS_PIPELINE = {"team": "people-analytics", "pipeline": "retention-risk", "env": "prod"}
```

### Aplicación en People Analytics
- **Patrón mínimo:** ningún PR a producción se mergea sin `description` en tablas y columnas críticas.
- **Auditoría rápida:** `SELECT table_name FROM region-eu.INFORMATION_SCHEMA.TABLES WHERE table_schema='gold_people_analytics' AND option_value IS NULL` → tablas sin descripción.

---

## Tema 6.10: Auditoría de queries con INFORMATION_SCHEMA

### Conceptos clave
- `INFORMATION_SCHEMA` es el "logbook automático" de BigQuery — registra cada query, cada job, cada modificación de schema.
- Sirve para 3 cosas: **FinOps** (¿qué nos cuesta más?), **gobierno** (¿quién accedió a la nómina?), **performance** (¿qué queries son lentas?).
- En PA es especialmente crítico porque debemos poder responder a un DPO: "muéstrame todos los accesos a `silver_personio.fact_payroll_monthly` en los últimos 90 días".

### Detalle técnico

**Vistas más útiles de INFORMATION_SCHEMA:**

| Vista | Para qué sirve | Retención |
|-------|----------------|-----------|
| `JOBS_BY_PROJECT` | Auditoría completa de queries | 180 días |
| `JOBS_BY_USER` | Queries del usuario actual | 180 días |
| `JOBS_BY_FOLDER` | Cross-project en una carpeta | 180 días |
| `JOBS_TIMELINE` | Slot-by-second (debugging perf) | 180 días |
| `TABLES` | Schema, tamaño, particionado | Tiempo real |
| `TABLE_STORAGE` | Bytes facturables logical/physical | Tiempo real |
| `COLUMN_FIELD_PATHS` | Schema columna por columna | Tiempo real |

**Las 4 queries de auditoría que hay que tener siempre listas:**

```sql
-- 1. Top 10 queries más caras de los últimos 7 días
SELECT
  user_email,
  job_id,
  total_bytes_processed / POW(1024, 3) AS gb_processed,
  total_bytes_processed / POW(1024, 4) * 5 AS estimated_cost_usd,
  query
FROM `region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND job_type = 'QUERY'
  AND state = 'DONE'
ORDER BY total_bytes_processed DESC
LIMIT 10;

-- 2. Coste por equipo (usando labels)
SELECT
  labels.value AS team,
  COUNT(*) AS jobs,
  SUM(total_bytes_processed) / POW(1024, 4) * 5 AS estimated_cost_usd
FROM `region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT,
  UNNEST(labels) AS labels
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND labels.key = 'team'
GROUP BY team
ORDER BY estimated_cost_usd DESC;

-- 3. Acceso a datos sensibles (auditoría DPO)
SELECT
  creation_time,
  user_email,
  query
FROM `region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  AND REGEXP_CONTAINS(query, r'(?i)(gross_salary|bonus_amount|national_id|iban)')
ORDER BY creation_time DESC;

-- 4. Tablas que crecen sin control
SELECT
  table_schema, table_name,
  ROUND(total_logical_bytes / POW(1024, 3), 2) AS gb_logical,
  ROUND(total_physical_bytes / POW(1024, 3), 2) AS gb_physical,
  ROUND((total_logical_bytes - active_logical_bytes) / POW(1024, 3), 2) AS gb_in_time_travel
FROM `region-eu`.INFORMATION_SCHEMA.TABLE_STORAGE
WHERE table_schema NOT LIKE '%temp%'
ORDER BY total_logical_bytes DESC
LIMIT 20;
```

### Aplicación en People Analytics
- **Caso del proyecto:** después de cada ejecución del pipeline, escribimos una fila en `pipeline_runs.retention_pipeline_runs` con: `run_id`, `start/end time`, `bytes_processed`, `slot_ms`, `rows_written`, `cost_usd`. Esto se cruzará con INFORMATION_SCHEMA para análisis FinOps en M12.
- **Caso de auditoría real:** un DPO pregunta "¿quién accedió a la nómina del CEO?". Query 3 arriba responde en segundos.

---

## Tema 6.11: Stored Procedures, UDFs y Procedural Language

### Conceptos clave
- **UDF (User Defined Function)**: una función SQL o JavaScript reutilizable. Se invoca como `mi_udf(args)`. Hace **una** cosa pequeña.
- **Stored Procedure (SP)**: un bloque de código procedural (LOOP, IF, DECLARE, BEGIN/EXCEPTION) que ejecuta múltiples statements y puede tomar inputs/outputs. Es la **unidad básica de un pipeline en BigQuery**.
- **Procedural Language**: la sintaxis BEGIN ... END, DECLARE, SET, IF, WHILE, LOOP, EXCEPTION dentro de SPs y scripts.

Estos tres elementos son lo que separa BigQuery de "una herramienta de queries" y la convierten en una **plataforma de procesamiento**.

### Detalle técnico

**UDF SQL — la herramienta más limpia para encapsular reglas de negocio:**

```sql
CREATE OR REPLACE FUNCTION gold_people_analytics.compa_ratio(
  salary FLOAT64,
  band_min FLOAT64,
  band_max FLOAT64
) RETURNS FLOAT64 AS (
  SAFE_DIVIDE(salary, (band_min + band_max) / 2)
);

CREATE OR REPLACE FUNCTION gold_people_analytics.tenure_bucket(
  hire_date DATE,
  snapshot_date DATE
) RETURNS STRING AS (
  CASE
    WHEN DATE_DIFF(snapshot_date, hire_date, MONTH) < 6 THEN '0_lt_6m'
    WHEN DATE_DIFF(snapshot_date, hire_date, MONTH) < 12 THEN '1_6_12m'
    WHEN DATE_DIFF(snapshot_date, hire_date, MONTH) < 36 THEN '2_1_3y'
    WHEN DATE_DIFF(snapshot_date, hire_date, MONTH) < 60 THEN '3_3_5y'
    ELSE '4_gt_5y'
  END
);
```

**UDF JavaScript — para lógica que SQL no puede expresar:**

```sql
CREATE OR REPLACE FUNCTION gold_people_analytics.normalize_country_code(input STRING)
RETURNS STRING
LANGUAGE js AS r"""
  const map = {'spain': 'ES', 'españa': 'ES', 'espana': 'ES',
               'united kingdom': 'GB', 'uk': 'GB', 'great britain': 'GB'};
  if (!input) return null;
  const k = input.toLowerCase().trim();
  return map[k] || input.toUpperCase().substring(0,2);
""";
```

(Las UDFs JS pesan más que las SQL — solo cuando es imprescindible.)

**Stored Procedure idempotente — el patrón estándar de pipeline:**

```sql
CREATE OR REPLACE PROCEDURE feature_store_retention.sp_build_retention_features(
  IN snapshot_month DATE
)
BEGIN
  DECLARE rows_written INT64;
  DECLARE start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

  -- Idempotencia: borrar la partición antes de reescribir
  DELETE FROM feature_store_retention.features
  WHERE snapshot_month = snapshot_month;

  -- Insert de las features del mes
  INSERT INTO feature_store_retention.features
  SELECT
    snapshot_month,
    e.employee_code,
    e.country,
    e.band,
    gold_people_analytics.tenure_bucket(e.hire_date, LAST_DAY(snapshot_month, MONTH)) AS tenure_bucket,
    gold_people_analytics.compa_ratio(p.gross_salary, b.band_min, b.band_max) AS compa_ratio,
    -- ... más features ...
  FROM silver_personio.dim_employee e
  LEFT JOIN silver_personio.fact_payroll_monthly p
    ON p.employee_code = e.employee_code AND p.payroll_month = snapshot_month
  LEFT JOIN gold_people_analytics.salary_bands b
    ON b.country = e.country AND b.band = e.band
  WHERE e.is_active_at(snapshot_month);

  SET rows_written = @@row_count;

  -- Log de ejecución para FinOps + observabilidad
  INSERT INTO pipeline_runs.retention_pipeline_runs
    (run_id, step, snapshot_month, rows_written, start_time, end_time, status)
  VALUES
    (GENERATE_UUID(), 'build_features', snapshot_month, rows_written,
     start_time, CURRENT_TIMESTAMP(), 'SUCCESS');

EXCEPTION WHEN ERROR THEN
  INSERT INTO pipeline_runs.retention_pipeline_runs
    (run_id, step, snapshot_month, rows_written, start_time, end_time, status, error_message)
  VALUES
    (GENERATE_UUID(), 'build_features', snapshot_month, 0,
     start_time, CURRENT_TIMESTAMP(), 'FAILED', @@error.message);
  RAISE USING MESSAGE = @@error.message;
END;
```

**Procedural Language — bucle de backfill con WHILE:**

```sql
CREATE OR REPLACE PROCEDURE feature_store_retention.sp_backfill_features(
  IN start_month DATE,
  IN end_month DATE
)
BEGIN
  DECLARE current_month DATE DEFAULT start_month;

  WHILE current_month <= end_month DO
    CALL feature_store_retention.sp_build_retention_features(current_month);
    SET current_month = DATE_ADD(current_month, INTERVAL 1 MONTH);
  END WHILE;
END;
```

### Aplicación en People Analytics
- **Caso del proyecto:** todo el pipeline mensual estará envuelto en SPs. Cloud Workflows (M5) los llamará con `bigquery.jobs.query` ejecutando `CALL sp_xxx(...)`.
- **Beneficio operacional:** la lógica de negocio vive en BQ, versionada con Git (Dataform en M8). El orquestador solo decide *cuándo* ejecutarla; el *qué* es responsabilidad del SP. Separación clean.

---

## Cierre del Módulo 6

### Lo que el alumno se lleva (declarativo)
- BigQuery en producción exige decisiones explícitas: dónde particionar, qué clusterizar, qué documentar, quién puede leer qué.
- Las **stored procedures** son la unidad real del pipeline — el orquestador (M5) solo las llama.
- INFORMATION_SCHEMA convierte el data warehouse en un sistema **observable y auditable** sin instrumentación adicional.
- La capa semántica (vistas + intermedias) elimina la pregunta "¿qué número es el bueno?" en las reuniones.

### Conexión con el proyecto e2e (notebook)
El notebook construye un **pipeline mensual de Retention Risk** que aplica los 11 temas a la vez, espejando la estructura del template *procurement* (setup → datos → features → modelo → decisión → serving → findings). Lo que aprenden no son ejemplos aislados — es un sistema completo, runnable, con observabilidad y guardarraíles de coste.

### Conexión con módulos siguientes
- **M5** orquestará los SPs construidos aquí (Workflows + Composer).
- **M7** (SQL avanzado) usará las window functions ya empleadas en `sp_build_retention_features` para casos más sofisticados.
- **M8** (Dataform) versionará estos SPs con Git y CI/CD.
- **M11** (Cloud DLP) añadirá detección automática de PII a las features.
- **M12** (FinOps) profundizará en `INFORMATION_SCHEMA.JOBS_*` para reservaciones y BI Engine.
- **M15** (Vertex AI) sustituirá el BQML logistic por modelos más sofisticados, importándolos al Model Registry.

### Test de conceptos (preguntas tipo)
1. ¿Por qué `require_partition_filter = TRUE` es preferible a confiar en que los analistas filtren manualmente?
2. ¿Cuál es la diferencia entre time travel y un snapshot? ¿Cuándo usar cada uno?
3. ¿Qué expone una *authorized view* y qué oculta? ¿Cómo se diferencia de una vista normal?
4. Si tu tabla tiene 10 GB y particionas por una columna con 365 valores únicos, ¿cuánto debería leer una query con `WHERE date = '2025-01-15'`?
5. ¿Por qué un Stored Procedure con DELETE+INSERT es idempotente? ¿Qué pasaría con un INSERT solo?
6. ¿Cuál es el impacto de añadir labels a tus jobs?

### Recursos
- [Best Practices for Cost Optimization](https://cloud.google.com/bigquery/docs/best-practices-costs)
- [Partitioned Tables](https://cloud.google.com/bigquery/docs/partitioned-tables)
- [INFORMATION_SCHEMA Reference](https://cloud.google.com/bigquery/docs/information-schema-intro)
- [Procedural Language](https://cloud.google.com/bigquery/docs/reference/standard-sql/procedural-language)
- [Authorized Views](https://cloud.google.com/bigquery/docs/authorized-views)
