# Sesión 3 — Análisis profundo y guion docente

**Lunes 4 de mayo, 2026 — 16:00–18:00**
**Módulos cubiertos:** M5 (Orquestación) + M6 (BigQuery buenas prácticas) + Proyecto integrador
**Caso de negocio:** Pipeline mensual de **Retention Risk** sobre 209 empleados anonimizados de Personio.

---

## Índice

1. [Mensaje central de la sesión](#1-mensaje-central-de-la-sesión)
2. [Arquitectura completa — recorrido visual](#2-arquitectura-completa--recorrido-visual)
3. [Inventario de recursos GCP](#3-inventario-de-recursos-gcp)
4. [Módulo 6 — el cerebro en BigQuery](#4-módulo-6--el-cerebro-en-bigquery)
5. [Módulo 5 — orquestación con Workflows](#5-módulo-5--orquestación-con-cloud-workflows)
6. [Integrador — Cloud Function + bus de eventos](#6-integrador--cloud-function--bus-de-eventos)
7. [Buenas prácticas embebidas (T6.1 a T6.11)](#7-buenas-prácticas-embebidas-t61-a-t611)
8. [Patrón de idempotencia heredada](#8-patrón-de-idempotencia-heredada)
9. [Modelo de coste newsvendor explicado paso a paso](#9-modelo-de-coste-newsvendor-explicado-paso-a-paso)
10. [Findings honestos — qué decir y qué no decir al cliente](#10-findings-honestos--qué-decir-y-qué-no-decir-al-cliente)
11. [Guion de clase — 120 minutos cronometrados](#11-guion-de-clase--120-minutos-cronometrados)
12. [Demo en vivo — checklist de ejecución](#12-demo-en-vivo--checklist-de-ejecución)
13. [Preguntas que harán los alumnos y respuestas](#13-preguntas-que-harán-los-alumnos-y-respuestas)
14. [Estado de validación + bloqueos IAM](#14-estado-de-validación--bloqueos-iam)

---

## 1. Mensaje central de la sesión

> **"Un modelo de retención no produce predicciones, produce decisiones."**

Esta frase abre la clase. Es la idea que une los 3 notebooks y que justifica la regla newsvendor (Cu/Co). Si los alumnos solo recuerdan una cosa, que sea esto. Lo demás es mecánica.

Subordinadas:

- **El cerebro vive en BigQuery** (M6: SPs + UDFs + BQML), no en Python ni en Airflow.
- **La orquestación elige cuándo correr el cerebro** (M5: Workflows + Scheduler + Eventarc).
- **El bus de eventos elige por qué correr el cerebro** (Integrador: Cloud Function + Pub/Sub).
- **Idempotencia heredada**: cada capa la hereda gratis si la base la respeta.
- **GDPR Art. 22**: el output es input para HRBP, **no decisión final**.

---

## 2. Arquitectura completa — recorrido visual

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  M1+M2 — Datos reales Personio (capa Silver)                                 │
│  silver_personio.fact_salary_history  +  silver_personio.dim_employee        │
└────────────────┬─────────────────────────────────────────────────────────────┘
                 │
                 │ LAG() detecta transiciones reales (altas, bajas, cambios)
                 ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  M3 — Bus de eventos (Sesión 2)                                              │
│  Topic Pub/Sub `hr-events`  +  schema Avro registrado                        │
│  Eventos:  PAYROLL_CLOSED   ← solo este dispara el pipeline                  │
│            EMPLOYEE_HIRED                                                    │
│            EMPLOYEE_TERMINATED                                               │
│            SALARY_CHANGED                                                    │
└────────────────┬─────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  Integrador — Cloud Function gen2  `event-router-retention`                  │
│   1. decode base64 → JSON                                                    │
│   2. FILTRO: si event_type ≠ PAYROLL_CLOSED → ack y descartar                │
│   3. invoca Workflow con target_month, run_origin='event_driven'             │
│   4. structured logging JSON (Cloud Logging compatible)                      │
└────────────────┬─────────────────────────────────────────────────────────────┘
                 │
                 │  (alternativa paralela: Cloud Scheduler `0 6 1 * *` Madrid)
                 │  (alternativa paralela: Eventarc sobre payroll_*.csv en GCS)
                 ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  M5 — Cloud Workflow `retention-pipeline` (4 pasos lineales)                 │
│  ┌──────────────────────┐                                                    │
│  │ resolver_target_month│  asigna run_id=uuid()                              │
│  └─────────┬────────────┘                                                    │
│            ▼                                                                 │
│  ┌──────────────────────┐                                                    │
│  │ paso_1_build_features│  CALL sp_build_retention_features(target_month)    │
│  └─────────┬────────────┘                                                    │
│            ▼                                                                 │
│  ┌──────────────────────┐                                                    │
│  │ paso_2_score         │  CALL sp_score_retention(target_month)             │
│  └─────────┬────────────┘                                                    │
│            ▼                                                                 │
│  ┌──────────────────────┐                                                    │
│  │ paso_3_apply_decision│  CALL sp_apply_decision_rule(target_month)         │
│  └─────────┬────────────┘                                                    │
│            ▼                                                                 │
│  ┌──────────────────────┐                                                    │
│  │ paso_4_snapshot      │  CREATE SNAPSHOT TABLE  (try/except, nice-to-have) │
│  └─────────┬────────────┘                                                    │
│            ▼                                                                 │
│  ┌──────────────────────┐                                                    │
│  │ return_status        │  {status, target_month, run_id}                    │
│  └──────────────────────┘                                                    │
└────────────────┬─────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  M6 — Stored Procedures que escriben en BigQuery (idempotentes)              │
│                                                                              │
│  feature_store_retention.features                                            │
│      ↑ DELETE+INSERT por partición snapshot_month                            │
│  predictions_retention.scores                                                │
│      ↑ ML.PREDICT(retention_logistic_v1, features WHERE snapshot=target)     │
│  predictions_retention.retention_actions                                     │
│      ↑ JOIN scores × cost_params_retention → recomienda acción               │
│  predictions_retention.retention_actions_snapshot_YYYYMMDD                   │
│      ↑ snapshot inmutable, expiration 365 días                               │
│                                                                              │
│  → cada SP loguea SUCCESS/FAILED en pipeline_runs.retention_pipeline_runs    │
└────────────────┬─────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  Output final + observabilidad                                               │
│                                                                              │
│  • predictions_retention.retention_actions     (lista priorizada para HRBP)  │
│  • Vista semántica `v_retention_risk_dashboard`(authorized view, k-anon ≥5)  │
│  • Pub/Sub `retention-pipeline-status`         (notificaciones de éxito)     │
│  • Pub/Sub `retention-pipeline-alerts`         (notificaciones de fallo)     │
│  • Pub/Sub `hr-events-dlq`                     (mensajes veneno)             │
│  • pipeline_runs.retention_pipeline_runs       (audit log de cada step)      │
│  • INFORMATION_SCHEMA.JOBS_BY_USER             (FinOps por label step=...)   │
└──────────────────────────────────────────────────────────────────────────────┘
```

> Tienes el mismo diagrama editable en `architecture.drawio` (ábrelo en https://app.diagrams.net/ o con la extensión draw.io de VS Code).

---

## 3. Inventario de recursos GCP

### Datasets BigQuery creados en la sesión 3

| Dataset | Capa | Contiene | Creado en |
|---|---|---|---|
| `feature_store_retention` | feature store | `features` (particionada+clusterizada), SPs `sp_build_retention_features`, `sp_backfill_features` | M6 §1, §3, §6, §7 |
| `predictions_retention` | predictions | `scores`, `retention_actions`, `scores_test` (vista), snapshots, SPs `sp_score_retention`, `sp_apply_decision_rule` | M6 §9, §10, §12 |
| `ml_models` | ML registry | `retention_logistic_v1` (BQML LOGISTIC_REG) | M6 §9 |
| `pipeline_runs` | observabilidad | `retention_pipeline_runs` (log estructurado SP-by-SP, particionada por DATE(start_time)) | M6 §1 |

### Tablas existentes que se reutilizan (creadas en M1+M2)

| Tabla | Filas | Uso en sesión 3 |
|---|---|---|
| `silver_personio.dim_employee` | 209 | Maestro empleados; `termination_type='employee-quit'` define el label |
| `silver_personio.fact_salary_history` | 1,189 | Snapshots mensuales con `gross_salary_monthly_lc`, `status`, `hc_status`; fuente principal de features |
| `gold_people_analytics.cost_params_retention` | 5 | Cu/Co/τ\* por tier (junior, standard, senior, lead, manager) — config de la regla de decisión |

### UDFs (en `gold_people_analytics`)

| UDF | Firma | Lógica |
|---|---|---|
| `tenure_bucket` | `(hire_date, snapshot_date) → STRING` | 5 buckets: `0_lt_6m`, `1_6_12m`, `2_1_3y`, `3_3_5y`, `4_gt_5y` |
| `salary_delta_pct` | `(curr, prior) → FLOAT64` | `SAFE_DIVIDE(curr - prior, prior)` |
| `tier_from_position` | `(position) → STRING` | Regex sobre el título → junior/standard/senior/lead/manager |

### Servicios GCP desplegados

| Servicio | Recurso | Configuración |
|---|---|---|
| Cloud Workflows | `retention-pipeline` | Region `europe-southwest1`, 4 pasos, SA dedicada |
| Cloud Scheduler | `retention-pipeline-monthly` | Cron `0 6 1 * *`, time-zone Madrid, OAuth con SA |
| Eventarc | `retention-on-payroll-arrival` | Trigger sobre `gs://*-datalake/payroll/incoming/*` finalized |
| Cloud Function gen2 | `event-router-retention` | Python 3.11, trigger-topic `hr-events`, max-instances=5 |
| Pub/Sub topics | `hr-events`, `hr-events-dlq`, `retention-pipeline-status`, `retention-pipeline-alerts` | Status/alerts tienen pull subscriptions auditables |
| Service Account | `sa-workflows-retention` | 5 roles mínimos (least privilege) |

### IAM roles asignados

**A nivel proyecto (SA `sa-workflows-retention`):**
- `roles/bigquery.jobUser` — ejecutar queries
- `roles/bigquery.dataEditor` — `CALL` SPs que escriben
- `roles/pubsub.publisher` — publicar status/alerts
- `roles/logging.logWriter` — structured logs
- `roles/workflows.invoker` — auto-invocación

**A nivel proyecto (SA Compute Engine, para deploy de la Function — pendiente):**
- `roles/cloudfunctions.invoker`
- `roles/eventarc.eventReceiver`
- (más los 5 anteriores)

**A nivel dataset (granulares):**
| Dataset | Rol |
|---|---|
| `silver_personio` | READER |
| `gold_people_analytics` | READER |
| `feature_store_retention` | WRITER |
| `predictions_retention` | WRITER |
| `pipeline_runs` | WRITER |
| `ml_models` | WRITER |

---

## 4. Módulo 6 — el cerebro en BigQuery

**Archivo:** `modulo_06_bigquery_buenas_practicas/notebook.ipynb` (46 celdas, 122 KB).
**Estructura:** espejo de `04_baseline_procurement.ipynb` que vieron en clase 1.
**Filosofía:** este notebook **no es un experimento exploratorio**. Es la pinta real que tiene un Workbench notebook en producción: idempotente, observable, con guardarraíles de coste, documentación inline y output reproducible.

### 4.1 Setup + datasets de producción (celdas 0-4)

**T6.1 aplicado**: cada dataset se crea con `description` y `labels` explícitos:

```python
labels = {
    "team": "people-analytics",
    "pipeline": "retention-risk",
    "env": "prod",
    "layer": "feature_store"  # o "predictions", "ml_models", "observability"
}
```

**Por qué importan los labels:** se usan en INFORMATION_SCHEMA para filtrar coste por pipeline. Sin labels, no puedes hacer FinOps decente.

**Pregunta para alumnos:** *"¿qué pasa si alguien crea un dataset sin description?"* → respuesta: en 6 meses nadie sabe qué contiene, y nadie se atreve a borrarlo. Los datasets sin description son la primera señal de un equipo de datos inmaduro (M18).

### 4.2 Validación de la capa Silver (celdas 6-7)

Lectura honesta del label:
```sql
SELECT termination_type, COUNT(*) AS empleados
FROM silver_personio.dim_employee
GROUP BY termination_type
```

Resultado esperado: ~41% de empleados con `termination_type` no nulo. **Bandera roja.** Posibles explicaciones:
1. La empresa pasó por un downsizing.
2. El export histórico incluye leavers junto con activos.
3. Datos contaminados.

**Decisión metodológica:** solo `termination_type='employee-quit'` cuenta como label positivo. Las demás (`fired`, `contract-expired`) son decisiones de empresa y **no se pueden "prevenir"** con un modelo de retención.

### 4.3 Feature store: DDL con guardarraíles (celda 9)

```sql
CREATE TABLE feature_store_retention.features (
  snapshot_month DATE NOT NULL,
  employee_code  INT64 NOT NULL,
  country, team, position, tenure_months, tenure_bucket,
  gross_salary_monthly_lc, bonus_monthly_lc,
  compa_ratio_team, salary_delta_pct_6m,
  has_bonus, fte,
  voluntary_exit_within_3m INT64    -- LABEL
)
PARTITION BY snapshot_month
CLUSTER BY country, team
OPTIONS(
  description = "...",
  labels = [("team", "people-analytics"), ("pipeline", "retention-risk")],
  require_partition_filter = TRUE,    -- ⭐ guardarraíl
  partition_expiration_days = 730     -- 2 años de retención
)
```

**3 guardarraíles que tienes que destacar en pizarra:**

| Guardarraíl | Qué evita | Coste de NO ponerlo |
|---|---|---|
| `PARTITION BY snapshot_month` | Lecturas full-scan | Cada query lee 24 meses en lugar de 1 → 24× coste |
| `CLUSTER BY country, team` | Lecturas no-clusterizadas | Filtros por país son ~10× más lentos |
| `require_partition_filter = TRUE` | `SELECT *` accidentales | Un becario puede hacer una factura de 4 dígitos en 1 query |

**Pregunta trampa:** *"¿se puede particionar y clusterizar a la vez?"* → sí. La partición es el primer filtro grueso (días/meses), el clustering es el filtro fino dentro de cada partición.

### 4.4 Modelo de coste — newsvendor adaptado (celdas 11-13)

Ver §9 de este documento para el deep dive matemático completo.

Los parámetros viven en `gold_people_analytics.cost_params_retention`:

| tier | Cu_pct | Co_pct | tau_star |
|---|---|---|---|
| junior | 0.80 | 0.08 | 0.909 |
| standard | 1.00 | 0.10 | 0.909 |
| senior | 1.50 | 0.12 | 0.926 |
| lead | 1.80 | 0.12 | 0.938 |
| manager | 2.00 | 0.15 | 0.930 |

> **Decisión clave**: `cost_params_retention` es una **tabla de configuración**, no constante en código. La revisa Compensation cada 6 meses. Si Cu/Co cambian, el pipeline produce decisiones nuevas sin redeploy. Esto es un patrón M6 importante: **separa configuración de lógica**.

### 4.5 UDFs reutilizables (celda 15) — T6.11 parte 1

Tres UDFs SQL en `gold_people_analytics`. **Razones para usar UDFs en SQL en lugar de inline:**

1. **Reutilización**: `tenure_bucket` se llama desde el SP, desde la vista semántica, y desde queries ad-hoc.
2. **Versionable**: cuando Compensation pida cambiar las regex de `tier_from_position`, lo cambias en un sitio.
3. **Testeable**: las pruebas en celda 15 verifican casos borde (`Senior X`, `Office Manager`, `Junior Developer`).
4. **Documentable**: cada UDF tiene `OPTIONS(description="...")` que aparece en la consola de BQ.

**Anti-patrón que tienes que mencionar:** UDFs JavaScript para lógica simple. Son ~5× más lentas que UDFs SQL porque BQ tiene que invocar V8.

### 4.6 SP idempotente — `sp_build_retention_features` (celda 17) — T6.11 parte 2

Plantilla canónica que **toda la sesión 3 sigue al pie de la letra**:

```sql
CREATE OR REPLACE PROCEDURE feature_store_retention.sp_build_retention_features(
  IN target_month DATE
)
OPTIONS(description="...", strict_mode=false)
BEGIN
  DECLARE rows_written INT64 DEFAULT 0;
  DECLARE start_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
  DECLARE run_uuid STRING DEFAULT GENERATE_UUID();

  BEGIN
    -- 1. Idempotencia
    DELETE FROM feature_store_retention.features
    WHERE snapshot_month = target_month;

    -- 2. Recompute (CTEs anidados)
    INSERT INTO feature_store_retention.features
    WITH snapshot_now AS (...),
         snapshot_6m_ago AS (...),
         team_medians AS (...),         -- compa-ratio
         future_voluntary_exits AS (...) -- LABEL look-ahead 3 meses
    SELECT ...;

    SET rows_written = @@row_count;

    -- 3. Log SUCCESS
    INSERT INTO pipeline_runs.retention_pipeline_runs VALUES (...);

  EXCEPTION WHEN ERROR THEN
    -- 4. Log FAILED + RAISE
    INSERT INTO pipeline_runs.retention_pipeline_runs VALUES (..., 'FAILED', @@error.message);
    RAISE USING MESSAGE = @@error.message;
  END;
END
```

**4 patrones embebidos** que tienes que enseñar:

| Patrón | Mecanismo | Por qué importa |
|---|---|---|
| Idempotencia | `DELETE WHERE partition = target` antes del `INSERT` | Re-ejecuciones son seguras (Pub/Sub at-least-once) |
| Manejo de errores | `BEGIN ... EXCEPTION WHEN ERROR ... RAISE` | Si falla, queda registrado y la excepción burbujea |
| Audit log | `INSERT INTO pipeline_runs ... VALUES (...)` | Cada ejecución deja huella, sin Cloud Logging |
| Look-ahead label | `termination_date <= DATE_ADD(target_month, INTERVAL 3 MONTH)` | El label se calcula dentro del SP — no se filtra en Python |

**Pregunta trampa:** *"¿por qué `DELETE+INSERT` y no `MERGE`?"*
- `MERGE` requiere una clave compuesta y es más lento.
- `DELETE` por partición + `INSERT` aprovecha la partición física → casi gratis (BQ no escanea).
- En tablas pequeñas la diferencia no se ve, pero el patrón escala mejor.

### 4.7 Procedural Language: backfill con WHILE (celda 20) — T6.11 parte 3

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
END
```

**Por qué hacerlo en BQ y no en Python:**
1. Una sola transacción de orquestación → más fácil de monitorizar.
2. El estado vive en BQ, no en el cliente.
3. Reusable desde Cloud Workflows / Composer.
4. Si te quedas sin VM/notebook, el bucle sigue en BQ.

**Llamada en celda 21:** `CALL sp_backfill_features('2025-01-01', '2025-12-01')` → 12 ejecuciones del SP atómico.

### 4.8 Hold-out temporal y entrenamiento BQML (celdas 24-27)

**Decisión metodológica honesta — la frase para alumnos:**

> *"Nunca usamos datos del futuro para predecir el pasado."*

```python
TRAIN_MONTHS = ['2025-01-01', ..., '2025-08-01']  # 8 meses
TEST_MONTHS  = ['2025-09-01', '2025-10-01', '2025-11-01']  # 3 meses
# 2025-12 NO se usa: necesitaríamos datos hasta 2026-03 para observar el label
```

Modelo BQML:
```sql
CREATE OR REPLACE MODEL ml_models.retention_logistic_v1
OPTIONS(
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['voluntary_exit_within_3m'],
  auto_class_weights = TRUE,        -- desbalanceo
  data_split_method = 'NO_SPLIT',   -- ya lo hicimos manualmente
  enable_global_explain = TRUE,     -- feature importance
  l2_reg = 0.1
) AS
SELECT country, team, tenure_months, tenure_bucket, compa_ratio_team,
       salary_delta_pct_6m, has_bonus, fte,
       voluntary_exit_within_3m
FROM features WHERE snapshot_month IN (TRAIN_MONTHS)
```

**Por qué LOGISTIC_REG como baseline:**
- Interpretable (cada coef es leíble).
- Coste cero — vive en BQ.
- Si XGBoost no supera al logistic, **no merece la pena la complejidad operacional**.
- Es el "smell test" estándar en ML productivo.

**Resultado:** AUC ROC sobre TEST = **0.84**. → **Bandera roja.** Sospechosamente alto para 209 empleados. Probable overfit. Hay que decirlo al cliente antes de poner en prod.

### 4.9 SP de scoring + SP de decisión (celdas 28, 30)

Mismo patrón que `sp_build_retention_features`:

`sp_score_retention(target_month)`:
```sql
DELETE FROM scores WHERE snapshot_month = target_month;
INSERT INTO scores
SELECT snapshot_month, employee_code, country, team, position,
       voluntary_exit_within_3m AS actual_label,
       predicted_voluntary_exit_within_3m_probs[OFFSET(0)].prob AS prob_class_0,
       predicted_voluntary_exit_within_3m_probs[OFFSET(1)].prob AS prob_class_1,
       CURRENT_TIMESTAMP() AS scored_at
FROM ML.PREDICT(MODEL ml_models.retention_logistic_v1,
                (SELECT * FROM features WHERE snapshot_month = target_month));
```

`sp_apply_decision_rule(target_month)`:
```sql
DELETE FROM retention_actions WHERE snapshot_month = target_month;
INSERT INTO retention_actions
SELECT s.*,
       tier_from_position(s.position) AS tier,
       cp.tau_star,
       CASE
         WHEN prob_class_1 >= cp.tau_star         THEN 'retention_action'
         WHEN prob_class_1 >= cp.tau_star * 0.85  THEN 'monitor'
         ELSE 'no_action'
       END AS recommended_action,
       CASE
         WHEN prob_class_1 >= 0.95          THEN 1   -- prioridad máxima
         WHEN prob_class_1 >= cp.tau_star   THEN 2
         WHEN prob_class_1 >= cp.tau_star * 0.85 THEN 3
         WHEN prob_class_1 >= 0.5           THEN 4
         ELSE                                    5
       END AS priority,
       cp.Cu_pct AS replacement_cost_pct,
       cp.Co_pct AS retention_cost_pct,
       CURRENT_TIMESTAMP() AS scored_at
FROM scores s
JOIN cost_params_retention cp ON cp.tier = tier_from_position(s.position)
WHERE s.snapshot_month = target_month;
```

**Output final:** una fila por empleado activo con `recommended_action ∈ {retention_action, monitor, no_action}` y `priority ∈ {1..5}`.

### 4.10 Comparison plot — modelo vs naive (celda 33)

Espejo del template procurement. Compara coste esperado total bajo 3 reglas:
1. **Modelo logistic** parametrizado por τ.
2. **Naive: actuar sobre todos** (τ=0).
3. **Naive: no actuar sobre nadie** (τ=1).

**Si el modelo no supera al naive, no merece la pena ponerlo en producción.**

El plot tiene 2 paneles:
- Izquierda: coste esperado vs τ.
- Derecha: # empleados con acción de retención vs τ.

Esta sección es **el momento de la verdad metodológica**: aquí se ve si el modelo aporta valor real o si es teatro estadístico.

### 4.11 Capa semántica + authorized views + snapshots (celdas 35-37)

**Tres patrones en una sección:**

**(a) Vista semántica** `gold_people_analytics.v_retention_risk_dashboard`:
```sql
CREATE OR REPLACE VIEW v_retention_risk_dashboard AS
SELECT snapshot_month, country, team, tier, recommended_action, priority,
       COUNT(*) AS empleados,
       ROUND(AVG(retention_risk_score), 3) AS avg_score,
       ROUND(AVG(tau_star), 3) AS avg_threshold
FROM predictions_retention.retention_actions
GROUP BY 1,2,3,4,5,6
HAVING COUNT(*) >= 5    -- ⭐ k-anonymity
```

> **k-anonymity ≥5** = nunca exponer cohortes de menos de 5 personas. Si solo hay 1 senior en Brazil, no aparece en el dashboard. Esto bloquea la re-identificación. **GDPR-friendly por diseño.**

**(b) Authorized view:**
```python
ds_preds.access_entries.append(bigquery.AccessEntry(
    role=None,
    entity_type="view",
    entity_id={"projectId": ..., "datasetId": "gold_people_analytics", "tableId": "v_retention_risk_dashboard"},
))
bq_client.update_dataset(ds_preds, ["access_entries"])
```

**Patrón:** HRBP puede consultar `v_retention_risk_dashboard` sin tener acceso a `predictions_retention.retention_actions` (que tiene scores individuales). La vista actúa como **proxy de seguridad**.

**(c) Snapshots inmutables** (celda 37):
```sql
CREATE SNAPSHOT TABLE retention_actions_snapshot_20251101_20260504
CLONE retention_actions
OPTIONS(
  expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 365 DAY),
  description = "Snapshot de auditoría — decisiones del pipeline para snapshot_month 2025-11-01"
)
```

**Coste de almacenamiento ≈ 0** mientras la base no diverja (BQ snapshots son delta-encoded).

### 4.12 INFORMATION_SCHEMA cost audit (celdas 39-40) — T6.10

Filtro por `labels.pipeline='retention-risk'` para aislar el coste del pipeline:

```sql
SELECT step_label.value AS step,
       COUNT(*) AS jobs,
       ROUND(SUM(total_bytes_billed) / POW(1024, 4) * 5, 4) AS estimated_cost_usd,
       ROUND(SUM(total_slot_ms) / 1000.0, 1) AS slot_seconds,
       ROUND(AVG(TIMESTAMP_DIFF(end_time, start_time, MILLISECOND))/1000.0, 2) AS avg_duration_s
FROM `region-europe-southwest1`.INFORMATION_SCHEMA.JOBS_BY_USER j,
  UNNEST(j.labels) AS step_label
WHERE j.creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  AND step_label.key = 'step'
  AND EXISTS (SELECT 1 FROM UNNEST(j.labels) AS l
              WHERE l.key = 'pipeline' AND l.value = 'retention-risk')
GROUP BY step
```

**Nota:** `JOBS_BY_USER` requiere `roles/bigquery.user` (siempre disponible). `JOBS_BY_PROJECT` da más detalle pero requiere `roles/bigquery.resourceViewer`. En producción con SA dedicada, preferir `JOBS_BY_PROJECT`.

Crucemos con `pipeline_runs.retention_pipeline_runs`:
- `pipeline_runs` te dice **qué pasó** (status SUCCESS/FAILED, rows_written, error_message).
- `INFORMATION_SCHEMA` te dice **cuánto costó** (bytes, slot-ms, duración).

Las dos juntas = retrato completo. En M12 (FinOps) lo conectamos a BI Engine.

### 4.13 GenAI brief stub (celda 42) + Vertex AI Model Registry (celda 44)

**Foreshadowing M16 y M15.** Hoy es código comentado/placeholder:
- `build_retention_brief()` produce un texto Python plano. En M16 se reemplaza por una llamada a Gemini 1.5 Pro.
- El bloque Vertex AI Model Registry está comentado completo. En M15 se descomenta.

**Pedagogía:** los alumnos ven dónde encaja la pieza futura sin sufrir la complejidad ahora.

---

## 5. Módulo 5 — orquestación con Cloud Workflows

**Archivo:** `modulo_05_orquestacion_pipelines/notebook.ipynb` (26 celdas, 34 KB)
**Filosofía:** la lógica ya vive en BigQuery (M6); aquí decidimos **cuándo y cómo** ejecutarla.

### 5.1 Verificación de prerequisitos (celda 3)

Lista 8 recursos M6 (datasets, tablas, routines). Si falta uno → `RuntimeError`. **Patrón fail-fast.**

```python
PREREQS = [
    ("dataset",   "feature_store_retention"),
    ("dataset",   "predictions_retention"),
    ("dataset",   "pipeline_runs"),
    ("table",     "feature_store_retention.features"),
    ("table",     "predictions_retention.retention_actions"),
    ("table",     "pipeline_runs.retention_pipeline_runs"),
    ("routine",   "feature_store_retention.sp_build_retention_features"),
    ("routine",   "predictions_retention.sp_apply_decision_rule"),
]
```

### 5.2 Comparativa Workflows vs Composer (celda 6) — tabla decisional

| Pregunta | Workflows | Composer |
|---|---|---|
| Coste mínimo mensual | ~0€ | ~$300/mes (cluster GKE) |
| Cold start | <1s | ~25 min |
| Mantenimiento del runtime | GCP | GCP (pero el cluster es tuyo) |
| Lenguaje | YAML declarativo | Python (DAGs Airflow) |
| Reintentos / backoff | Sí, en YAML | Sí, en `default_args` |
| Backfills automáticos | No | `catchup=True` |
| Operadores de terceros | Limitado | Cientos (dbt, Snowflake, Slack…) |
| UI | Básica (consola) | Rica (Airflow UI) |
| Curva de aprendizaje | Baja | Media-alta |
| Mejor para… | <10 pipelines GCP-only | >10 pipelines, cross-system |

**Recomendación PA:** Workflows. La complejidad real del 80% de los casos no necesita Airflow.

**Argumento defensivo si un alumno protesta** *("Airflow es estándar de la industria")*:
- Airflow es estándar **dentro del ecosistema dato-cross-cloud**. Para pipelines GCP-only, es overkill.
- $300/mes × 12 = $3,600/año. Para People Analytics con 4-5 pipelines, no se amortiza.
- En M9 (GitHub) versionamos el YAML como código → CI/CD = deploy automático.

### 5.3 Workflow YAML — anatomía (`workflows/retention_pipeline.yaml`)

```yaml
main:
  params: [args]
  steps:
    - resolver_target_month:
        assign:
          - target_month: '${args.target_month}'
          - project_id: project-9176af0b-ecb3-4050-859
          - run_id: '${uuid.generate()}'

    - paso_1_build_features:
        call: googleapis.bigquery.v2.jobs.query
        args:
          projectId: '${project_id}'
          body:
            query: ${"CALL `" + project_id + ".feature_store_retention.sp_build_retention_features`(DATE \"" + target_month + "\")"}
            useLegacySql: false
            labels:
              pipeline: retention-risk
              step: build_features
              env: prod
            maximumBytesBilled: "53687091200"   # 50 GB

    - paso_2_score:           # idéntico patrón
    - paso_3_apply_decision:  # idéntico patrón
    - paso_4_snapshot:
        try:
          call: googleapis.bigquery.v2.jobs.query
          args: ...
        except:
          as: e
          steps:
            - swallow_snapshot_error:
                assign:
                  - snapshot_status: failed_but_continuing

    - return_status:
        return:
          status: SUCCESS
          target_month: '${target_month}'
          run_id: '${run_id}'
```

**Detalles que tienes que destacar:**

| Detalle | Línea | Por qué importa |
|---|---|---|
| `${args.target_month}` | 30 | Parámetro de entrada — obligatorio en cada invocación |
| `${uuid.generate()}` | 32 | run_id único por ejecución → trazabilidad |
| `labels.step` | 44, 60, 76, 93 | FinOps por paso — cruzable con INFORMATION_SCHEMA |
| `maximumBytesBilled: "53687091200"` | 48 | Guardarraíl de coste — 50 GB max por step (T6.3) |
| `try / except` en paso_4 | 86-103 | Snapshot es nice-to-have, no aborta el pipeline si falla |
| `text.replace_all()` + `time.format()` en snapshot name | 91 | Nombre de snapshot construido dinámicamente: `retention_actions_snap_20251101_20260504` |

**Bloques comentados** (líneas 119-138): logging y Pub/Sub publish. Requieren `roles/logging.logWriter` y `roles/pubsub.publisher`. En el curso están comentados; en producción se descomentan.

### 5.4 Service Account dedicada (celda 5) — least privilege

```python
SA_WORKFLOWS_NAME = "sa-workflows-retention"
ROLES = [
    "roles/bigquery.jobUser",      # ejecutar queries
    "roles/bigquery.dataEditor",   # CALL SPs que escriben
    "roles/pubsub.publisher",      # publicar status/alerts
    "roles/logging.logWriter",     # logs estructurados
    "roles/workflows.invoker",     # auto-invocación
]
```

**Patrón M2 + M11**: nunca usar la SA de Compute Engine por defecto. Crea una SA con propósito y dale **solo lo que necesita**. Esto se audita en M11.

### 5.5 Despliegue con `gcloud` (celdas 8-9)

```bash
gcloud workflows deploy retention-pipeline \
  --location=europe-southwest1 \
  --source=workflows/retention_pipeline.yaml \
  --service-account=sa-workflows-retention@PROJECT.iam.gserviceaccount.com \
  --description="Pipeline mensual de retention risk (orquesta SPs de M6)"
```

**Cada deploy crea una nueva versión.** Las anteriores se conservan (rollback fácil desde consola).

### 5.6 Topics Pub/Sub para notificación (celda 11)

| Topic | Propósito | Suscriptor típico (futuro) |
|---|---|---|
| `retention-pipeline-status` | un msg por éxito | BigQuery Subscription → tabla métricas (M17) |
| `retention-pipeline-alerts` | un msg por fallo | Cloud Function → Slack/PagerDuty (M17) |

Las pull subscriptions `*-pull` son para que el alumno pulse mensajes desde el notebook y los vea.

### 5.7 Ejecución manual (celdas 13-16)

```bash
gcloud workflows execute retention-pipeline \
  --location=europe-southwest1 \
  --data='{"target_month":"2025-11-01"}'
```

**Polling de estado** (celda 14): cada 10s hasta que `state ∈ {SUCCEEDED, FAILED, CANCELLED}`, máximo 5 min.

**Resultado típico:** SUCCEEDED en ~16 segundos para 4 pasos (sobre 109 empleados activos en 2025-11).

### 5.8 Doble disparador: Scheduler + Eventarc (celdas 18, 20)

**Cloud Scheduler** — garantía temporal:
```bash
gcloud scheduler jobs create http retention-pipeline-monthly \
  --schedule="0 6 1 * *" \
  --time-zone="Europe/Madrid" \
  --uri="https://workflowexecutions.googleapis.com/v1/projects/.../executions" \
  --http-method=POST \
  --message-body='{"argument": "{}"}' \
  --oauth-service-account-email=sa-workflows-retention@...
```

**Eventarc** — trigger por evento real:
```bash
gcloud eventarc triggers create retention-on-payroll-arrival \
  --destination-workflow=retention-pipeline \
  --event-filters=type=google.cloud.storage.object.v1.finalized \
  --event-filters=bucket=PROJECT-datalake \
  --service-account=sa-workflows-retention@...
```

**Coexisten** — la idempotencia hace que sea seguro:
- Si payroll cierra el día 3 y deja un fichero CSV → Eventarc dispara → pipeline corre.
- El día 1 a las 06:00 también dispara Scheduler → pipeline corre con `target_month` ya procesado.
- El SP `DELETE+INSERT` por partición → ambas ejecuciones producen el mismo resultado.

**Argumento de negocio:**
- **Scheduler:** "garantía SLA de que el pipeline corre el día 1 incluso si payroll no llega".
- **Eventarc:** "acelera la ejecución si payroll llega antes" (típicamente día 3-4).

### 5.9 Composer DAG equivalente (celdas 22-23) — solo lectura

`composer/retention_pipeline_dag.py` traduce el YAML a Airflow. **No se despliega** — un cluster Composer cuesta ~$300/mes y arranca en 25 min.

**Tabla comparativa lado a lado** (celda 23):

| Aspecto | Workflows YAML | Airflow DAG |
|---|---|---|
| Sintaxis | YAML declarativo | Python |
| Definir step | `- name: { call:…, args:… }` | `task = Operator(...)` |
| Reintentos | `retry: { max_retries: 3 }` | `retries=3, retry_delay=timedelta(...)` |
| Manejo de error | `try / except as e` | `trigger_rule=ONE_FAILED` downstream |
| Orden de ejecución | Implícito (orden lineal) | Explícito (`task1 >> task2`) |
| Variables dinámicas | `${...}` (CEL) | `{{ ds }}` (Jinja) |
| Scheduling | Externo (Cloud Scheduler) | Built-in (`schedule_interval`) |

---

## 6. Integrador — Cloud Function + bus de eventos

**Archivo:** `sesion_03_proyecto_e2e/notebook.ipynb` (30 celdas, 46 KB)
**Filosofía:** **una sola pieza nueva** — la Function `event-router-retention`. Todo lo demás se reutiliza.

### 6.1 Verificación cross-módulo (celda 3)

Valida M3 (topic `hr-events` existe), M5 (Workflow ACTIVE), M6 (3 SPs existen). Si falla cualquiera → instrucciones explícitas de qué notebook re-ejecutar.

### 6.2 Eventos sintéticos derivados de datos reales (celdas 5-6)

**Truco didáctico potente:** los eventos **no son random**. `LAG()` sobre `fact_salary_history` detecta transiciones reales:

```sql
WITH consecutive_snapshots AS (
  SELECT employee_code, snapshot_date, status, hc_status, gross_salary_monthly_lc,
         LAG(status) OVER (PARTITION BY employee_code ORDER BY snapshot_date) AS prev_status,
         LAG(hc_status) OVER (PARTITION BY employee_code ORDER BY snapshot_date) AS prev_hc_status,
         LAG(gross_salary_monthly_lc) OVER (PARTITION BY employee_code ORDER BY snapshot_date) AS prev_salary
  FROM fact_salary_history
  WHERE snapshot_date BETWEEN '2025-09-01' AND '2025-11-01'
)
SELECT 'EMPLOYEE_HIRED'        FROM consecutive_snapshots WHERE prev_hc_status IS NULL AND hc_status='ALTA'
UNION ALL
SELECT 'EMPLOYEE_TERMINATED'   FROM consecutive_snapshots WHERE prev_status='active' AND status='inactive'
UNION ALL
SELECT 'SALARY_CHANGED'        FROM consecutive_snapshots WHERE ABS(curr-prev)/prev > 0.03
```

**Total publicado:** 3 PAYROLL_CLOSED (sintéticos, uno por mes) + 15 eventos derivados (ruido del bus).

**Solo PAYROLL_CLOSED dispara el pipeline.** El filtrado vive en la Function.

### 6.3 Schema Avro (celda 8) — contrato del bus

```json
{
  "type": "record",
  "name": "HrEvent",
  "fields": [
    {"name": "event_id",        "type": "string"},
    {"name": "event_type",      "type": "string"},
    {"name": "event_timestamp", "type": "string"},
    {"name": "target_month",    "type": ["null", "string"]},
    {"name": "source",          "type": "string"},
    {"name": "payload",         "type": "string"}
  ]
}
```

> **Nota didáctica:** registramos el schema pero publicamos sin schema-aware en este demo. El schema queda como contrato documentado. En producción se vincularía al topic con `--schema=hr-events-schema --message-encoding=JSON`.

### 6.4 Cloud Function gen2 — código embebido (celda 10)

**Patrón Workbench:** el código Python vive como **string Python** en una celda. Se escribe a `/tmp/cf_event_router/main.py` y se despliega con `gcloud`.

```python
import base64, json, logging, os
import functions_framework
from google.cloud.workflows import executions_v1

PROJECT_ID = os.environ.get("GCP_PROJECT", "")
WORKFLOW_LOCATION = os.environ.get("WORKFLOW_LOCATION", "europe-southwest1")
WORKFLOW_NAME = os.environ.get("WORKFLOW_NAME", "retention-pipeline")

_executions_client = executions_v1.ExecutionsClient()
logger = logging.getLogger("event-router")

@functions_framework.cloud_event
def event_router(cloud_event):
    try:
        # 1. Decodificar
        msg_b64 = cloud_event.data["message"]["data"]
        payload = json.loads(base64.b64decode(msg_b64).decode("utf-8"))
        event_id, event_type = payload.get("event_id"), payload.get("event_type")

        logger.info(json.dumps({"severity": "INFO", "event_id": event_id, "event_type": event_type, "decision": "received"}))

        # 2. FILTRO
        if event_type != "PAYROLL_CLOSED":
            logger.info(json.dumps({"severity": "INFO", "event_id": event_id, "decision": "ignored"}))
            return

        target_month = payload.get("target_month")
        if not target_month:
            logger.error(json.dumps({"severity": "ERROR", "decision": "rejected", "reason": "missing target_month"}))
            raise ValueError("PAYROLL_CLOSED event missing target_month")

        # 3. Disparar Workflow
        parent = f"projects/{PROJECT_ID}/locations/{WORKFLOW_LOCATION}/workflows/{WORKFLOW_NAME}"
        execution = executions_v1.Execution(
            argument=json.dumps({
                "target_month": target_month,
                "run_origin": "event_driven",
                "trigger_event_id": event_id,
            }),
        )
        op = _executions_client.create_execution(parent=parent, execution=execution)

        logger.info(json.dumps({"severity": "INFO", "event_id": event_id,
                                "decision": "workflow_triggered", "execution_name": op.name}))
    except Exception as e:
        logger.error(json.dumps({"severity": "ERROR", "decision": "function_error",
                                 "error_type": type(e).__name__, "error_message": str(e)[:500]}))
        raise  # NACK → Pub/Sub reintenta → DLQ después de N fallos
```

**Despliegue gen2** (celda 12):
```bash
gcloud functions deploy event-router-retention \
  --gen2 \
  --runtime=python311 \
  --region=europe-southwest1 \
  --source=/tmp/cf_event_router \
  --entry-point=event_router \
  --trigger-topic=hr-events \
  --set-env-vars=GCP_PROJECT=...,WORKFLOW_LOCATION=...,WORKFLOW_NAME=retention-pipeline \
  --memory=256Mi \
  --timeout=120s \
  --max-instances=5
```

**Por qué gen2 y no gen1:**
- Construido sobre Cloud Run → mejor cold start (~3-5s vs ~10s gen1).
- Escalado más fino (`max-instances`).
- Trigger nativo a Eventarc (gen1 es topic-direct).

### 6.5 Pull subscription para auditoría (celda 14)

`hr-events-audit-integrator` — subscription pull paralela al trigger Eventarc. Permite ver "qué llegó al bus" desde el notebook mientras la Function actúa en paralelo.

**Nota técnica:** las subscriptions son **independientes**. Cada subscription recibe **una copia** del mensaje. La Function consume con su propia subscription auto-creada por Eventarc.

### 6.6 End-to-end run en vivo (celdas 16-19)

```python
# 1. Publicar 18 eventos
for evento in eventos_a_publicar:
    f = publisher.publish(topic_path, json.dumps(evento).encode("utf-8"),
                          event_type=evento["event_type"], source=evento["source"])
    futures.append((evento, f))

# 2. Esperar 60s para procesamiento
time.sleep(60)

# 3. Verificar pipeline_runs
df_runs = bq_client.query("""
  SELECT step, snapshot_month, status, rows_written, ROUND(duration_seconds, 2) AS dur_s
  FROM pipeline_runs.retention_pipeline_runs
  WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)
""").to_dataframe()

# 4. Verificar retention_actions
df_actions = bq_client.query("""
  SELECT snapshot_month, recommended_action, COUNT(*) AS empleados
  FROM predictions_retention.retention_actions
  WHERE scored_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE)
  GROUP BY 1,2
""").to_dataframe()
```

**Resultado esperado:**
- 3 ejecuciones del Workflow (una por PAYROLL_CLOSED).
- 9 filas en `pipeline_runs` (3 meses × 3 steps: build_features, score, apply_decision).
- ~327 filas en `retention_actions` (109 empleados activos × 3 meses).

### 6.7 Dead Letter Queue (celda 21) — patrón M4

```python
evento_malformado = {
    "event_id": "poison-test-1",
    "event_type": "PAYROLL_CLOSED",
    "target_month": None,    # ⚠️ rompe la Function
    ...
}
publisher.publish(topic_path, json.dumps(evento_malformado).encode("utf-8"))
```

**Flujo de fallo:**
1. La Function recibe el evento.
2. `raise ValueError("missing target_month")`.
3. Pub/Sub no recibe ack → reintenta.
4. Tras 5 fallos consecutivos → mensaje a `hr-events-dlq`.
5. Suscriptor del DLQ (futuro M17) → notifica.

**Pregunta para alumnos:** *"¿la idempotencia nos protege de mensajes veneno?"* → No. La idempotencia protege contra duplicados, no contra payloads malformados. El DLQ es la red de seguridad complementaria.

### 6.8 Backfill por replay (celda 23)

```python
# Republicar PAYROLL_CLOSED para 2025-09 y 2025-10
for snapshot_month in ['2025-09-01', '2025-10-01']:
    evt = {
        "event_id": f"backfill-{snapshot_month}-{int(time.time())}",
        "event_type": "PAYROLL_CLOSED",
        "target_month": snapshot_month,
        "source": "backfill-script",
        "payload": json.dumps({"reason": "model_v2_rerun"}),
    }
    publisher.publish(topic_path, json.dumps(evt).encode("utf-8"))
```

**Idempotencia heredada en acción.** Re-publicas → la Function dispara → el Workflow corre → el SP hace `DELETE+INSERT` → no hay duplicados.

**Patrón de producción:** "si descubrimos un bug en el modelo y queremos recalcular 3 meses, no modificamos SQL. **Republicamos eventos**." Esto es event-sourcing puro.

### 6.9 Observabilidad cross-pipeline (celdas 25-26)

**3 fuentes combinadas:**
1. `pipeline_runs.retention_pipeline_runs` — qué SP corrió, cuándo, status.
2. `gcloud functions logs read event-router-retention` — qué eventos vio la Function, qué decidió.
3. `INFORMATION_SCHEMA.JOBS_BY_USER` con `WHERE labels.pipeline='retention-risk'` — coste por step.

**Vista combinada** (celda 26): "qué pasó en los últimos 15 minutos" en una query.

### 6.10 GenAI brief stub (celda 28) — foreshadowing M16

`brief_retention(snapshot_month)` produce un texto plano hoy. En M16 se reemplaza por una llamada a Gemini con prompt contextualizado.

---

## 7. Buenas prácticas embebidas (T6.1 a T6.11)

Inventario completo de los 11 temas del Módulo 6 y dónde se materializan:

| # | Tema | Dónde | Mensaje docente |
|---|---|---|---|
| T6.1 | Modelado de datasets de producción | M6 §1 (celda 4) | Description + labels obligatorios. Sin esto, FinOps imposible. |
| T6.2 | Particionado y clustering | M6 §3 (celda 9) | `require_partition_filter=TRUE` es el guardarraíl que evita facturas asesinas |
| T6.3 | Control de coste por query | M6 §6 (celda 17), M5 YAML | `maximumBytesBilled` + `labels.step` en cada job |
| T6.4 | Optimización (predicate pushdown) | M6 §6 SP build (filtros antes de JOINs) | Filtros de partición se aplican antes que cualquier JOIN |
| T6.5 | Permisos por dataset/tabla | M6 §12 (celda 36 — authorized view) | HRBP lee la vista sin acceso a la tabla base |
| T6.6 | Capa semántica | M6 §12 (celda 35) | `v_retention_risk_dashboard` es **única fuente de verdad** para Looker |
| T6.7 | Versionado de modelos | M6 §9 (`retention_logistic_v1`) | Sufijo `_v1` → `_v2` cuando reentrenes; conservas histórico |
| T6.8 | Snapshots de auditoría | M6 §12 (celda 37), M5 paso 4 | Snapshots delta-encoded → casi gratis; auditoría 1 año |
| T6.9 | Documentación con OPTIONS(description=…) | Toda DDL en M6 | Si no está documentado, no existe (M18) |
| T6.10 | Auditoría con INFORMATION_SCHEMA + pipeline_runs | M6 §13 (celdas 39-40) | Las dos juntas = "qué pasó" + "cuánto costó" |
| T6.11 | Stored Procs + UDFs + Procedural Language | M6 §5 (celda 15), §6 (celda 17), §7 (celda 20) | El cerebro vive en BQ, no en Python |

---

## 8. Patrón de idempotencia heredada

**La idea más importante de la sesión.** Aprender esto compensa toda la complejidad del pipeline.

### 8.1 Definición operativa

> "Re-ejecutar el pipeline para el mismo `target_month` produce el **mismo resultado** sin duplicar filas, sin filas huérfanas, sin race conditions visibles externamente."

### 8.2 Capa por capa, ¿quién garantiza qué?

| Capa | Mecanismo | Garantía local | Asume de la capa inferior |
|---|---|---|---|
| **SP** (`sp_build_retention_features`) | `DELETE WHERE partition = target` antes del `INSERT` | Re-ejecutar el SP no duplica filas en `features` | Nada. Es la base. |
| **Workflow** (`retention-pipeline`) | Llama al SP. No mantiene estado propio. | Re-ejecutar el Workflow no duplica nada | Que los SPs sean idempotentes |
| **Function** (`event-router-retention`) | Llama al Workflow. NACK → reintento → DLQ | Re-procesar un mensaje no duplica | Que el Workflow sea idempotente |
| **Pub/Sub at-least-once** | Reintentos automáticos hasta ack | Mensajes pueden llegar 1+ veces | Que el consumidor sea idempotente |

### 8.3 Consecuencias prácticas

- **Backfill por replay**: republicar eventos PAYROLL_CLOSED de hace 3 meses no rompe nada.
- **Mensajes duplicados de Pub/Sub**: la Function corre el Workflow 2 veces → el SP `DELETE+INSERT` → el mismo resultado.
- **Cold start fallido + reintento**: la Function muere a mitad de invocación → Pub/Sub reintenta → todo OK.

### 8.4 Lo que NO está cubierto por la idempotencia (cuidado)

1. **Race condition en MISMO mes** (dos Workflows simultáneos sobre `target_month=2025-11-01`) → último gana. En prod: `serializable_isolation` en SP, o singleton lock externo.
2. **Modelo cambiado entre runs** → `sp_score_retention` con modelo v2 produce scores distintos a v1 → eso es **drift, no bug**. Snapshots de auditoría capturan esto.
3. **Mensajes con payload distinto pero mismo `event_id`** → idempotencia event-driven a otro nivel; aquí no la implementamos.

---

## 9. Modelo de coste newsvendor explicado paso a paso

### 9.1 El problema de decisión

Cada empleado activo tiene una probabilidad `p` de irse en los próximos 3 meses (eso es lo que estima el modelo). El HRBP tiene 2 opciones:

- **A1: actuar** (bonus de retención, 1:1 con manager, plan de carrera). Coste: `Co × salario`.
- **A0: no actuar**. Coste si se va: `Cu × salario`.

### 9.2 Coste esperado de cada decisión

```
E[coste | actuar]    = Co × salario                    (siempre incurre)
E[coste | no actuar] = p × Cu × salario                (solo si se va)
```

### 9.3 ¿Cuándo actuar?

Actuar es óptimo cuando:
```
Co × salario  ≤  p × Cu × salario
Co            ≤  p × Cu
p             ≥  Co / (Cu)        ❌ no, espera...
```

Mejor: cuando el coste **incremental** de actuar (`Co - 0`) compensa la reducción esperada de coste (`p × Cu - 0`):
```
Co  ≤  p × Cu
```

Pero la regla clásica newsvendor pone el threshold simétrico:
```
τ* = Cu / (Cu + Co)
```

Esto viene de igualar costes esperados en un modelo de inventario. Para retención, es el threshold "balanceado" — donde el coste esperado de actuar igual al coste esperado de no actuar **cuando el modelo está bien calibrado**.

> **Decisión práctica:** actuamos si `score ≥ τ*`, con `τ* = Cu / (Cu + Co)`.

### 9.4 Valores numéricos del proyecto

```
Cu = 100% del salario anual  (coste de reemplazo, conservador)
     fuentes: estudios SHRM, Gallup → 50%-200% según nivel
Co = 10% del salario anual   (bonus de retención típico)
     fuentes: estudios Mercer → 5%-15%
τ* = 1.00 / (1.00 + 0.10) = 0.909
```

**Solo el top-decil (score ≥ 0.91) recibe acción.**

### 9.5 Por qué tier-aware

Un manager senior cuesta 2× su salario reemplazar (Cu=2.0). Un junior cuesta 0.8× (Cu=0.8). Por tanto:

| tier | Cu | Co | τ* |
|---|---|---|---|
| junior | 0.80 | 0.08 | 0.909 |
| standard | 1.00 | 0.10 | 0.909 |
| senior | 1.50 | 0.12 | 0.926 |
| lead | 1.80 | 0.12 | 0.938 |
| manager | 2.00 | 0.15 | 0.930 |

El threshold sube con el tier porque Co también sube (bonus de retención de un manager es más caro que el de un junior). Si solo subiera Cu, τ\* bajaría → "actúa siempre que dudes" sobre managers.

### 9.6 Cómo se materializa

`predictions_retention.retention_actions.recommended_action`:
- `score ≥ τ*` → `'retention_action'`
- `score ≥ 0.85 × τ*` → `'monitor'` (zona de vigilancia)
- `score < 0.85 × τ*` → `'no_action'`

Y `priority ∈ {1..5}` ordena dentro de cada bucket por urgencia.

### 9.7 Comparación honesta vs naive

El plot de la celda 33 compara **3 reglas**:
1. **Modelo logistic** parametrizado por τ.
2. **Naive: actuar sobre todos** (gastas Co en todos, ahorras todos los Cu, pero el coste total puede explotar).
3. **Naive: no actuar sobre nadie** (ahorras Co, pero pagas todos los Cu de los que se van).

**Si el modelo no supera al mejor naive, no merece la pena ponerlo en producción.** Esta es la pregunta honesta del proyecto.

---

## 10. Findings honestos — qué decir y qué no decir al cliente

### 10.1 Lo que funciona (di esto al cliente)

1. **Pipeline e2e idempotente** corre en ~16 segundos sobre 109 empleados activos.
2. **Regla de decisión defendible** ante negocio: cada acción tiene un coste comparado.
3. **Observabilidad por defecto**: `pipeline_runs` + `INFORMATION_SCHEMA` responden a "qué pasó el día X" en segundos.
4. **Particionado y `require_partition_filter`** evitan queries asesinas.
5. **Backfill por replay** es trivial (republicar PAYROLL_CLOSED).
6. **Authorized views + k-anonymity ≥5** dan un mínimo viable de governance.

### 10.2 Lo que NO funciona (di esto antes de prod)

1. **El dataset es minúsculo**: 209 empleados × 12 meses ≈ 2,500 filas. Cualquier métrica de validación tiene **incertidumbre enorme**. AUC=0.84 podría perfectamente ser AUC=0.55 con otro split.

2. **Tasa de exits del 41 %** es sospechosamente alta. O downsizing histórico, o export contaminado. **Pendiente: validar con cliente antes de poner en prod.**

3. **Label ruidoso**: `voluntary_exit_within_3m` se basa en `termination_type`, que en HR está mal codificado el ~10% de las veces (alguien que "se fue voluntariamente" para no ser despedido aparece como Voluntary).

4. **Variables omitidas críticas**: no tenemos satisfacción/engagement, performance review, manager NPS, jornada nocturna, viajes recientes. Lo que tenemos (compa-ratio, tenure, salary delta) explica una **fracción pequeña** del riesgo real.

5. **Sesgo potencial — bandera roja**: el modelo podría aprender a discriminar por `country` si las prácticas de offboarding difieren por cultura local. M11 (DLP + governance) tendrá que añadir tests de fairness por subgrupo.

6. **GDPR Art. 22**: prohíbe que una predicción afecte significativamente a un trabajador sin revisión humana. **El output del pipeline es input para HRBP, no decisión final.** Decirlo en negrita en el README al cliente.

### 10.3 Limitaciones técnicas a comunicar

| Limitación | Impacto | Mitigación |
|---|---|---|
| Cold start Function gen2 ~3-5s | Latencia primera invocación del día | `min-instances=1` si crítico |
| Race condition en MISMO mes | 2 Workflows paralelos sobre 2025-11 → último gana | Singleton lock o `serializable_isolation` |
| Pub/Sub at-least-once (no exactly-once) | Function muere entre CALL SP y ack → Workflow corre 2× | Idempotencia del SP cubre |
| DLQ requiere config manual de subscription | Mensajes veneno se pierden si DLQ no está configurado | Verificar en consola Pub/Sub que la subscription Eventarc tenga `--dead-letter-topic` |
| Eventarc requiere permisos de organización | Cuentas con CMEK/VPC-SC pueden requerir 2-3 vueltas con plataforma | Documentar el patrón y seguir |

---

## 11. Guion de clase — 120 minutos cronometrados

| Bloque | Tiempo | Contenido | Notebook | Acciones |
|---|---|---|---|---|
| **Repaso M3+M4** | 10 min | Pub/Sub, Eventarc, idempotencia básica, DLQ. **No abrir notebook** — recordar verbalmente. | — | Pizarra: dibujar el bus + DLQ + retry |
| **Frase de apertura** | 2 min | "Un modelo de retención no produce predicciones, produce decisiones." | — | Reacción de los alumnos. Anotar dudas. |
| **M6 §1-§4 — setup, datasets, modelo de coste** | 15 min | T6.1, validación Silver, parámetros Cu/Co/τ\* | M6 cells 0-13 | Mostrar cells 4 (datasets), 7 (target dist con 41%), 12 (cost params) |
| **M6 §5-§7 — UDFs + SP + Procedural Language** | 20 min | El cerebro: las 3 UDFs, el SP idempotente plantilla, el WHILE de backfill | M6 cells 15, 17, 20-22 | **Mostrar la plantilla SP en la pizarra** — DELETE+INSERT, BEGIN/EXCEPTION, log |
| **M6 §8-§10 — split temporal, BQML, decisión** | 15 min | Hold-out rolling-origin, AUC=0.84, comparison plot, regla newsvendor | M6 cells 24-33 | **Insistir en el comparison plot** — ¿supera al naive? |
| **M6 §11-§13 — capa semántica, snapshots, FinOps** | 8 min | Authorized view + k-anonymity, snapshots, INFORMATION_SCHEMA | M6 cells 35-40 | Mostrar el SQL de la vista con `HAVING COUNT(*) >= 5` |
| **PAUSA** | 5 min | — | — | — |
| **M5 §1-§3 — Workflows vs Composer + YAML** | 12 min | Tabla decisional, anatomía YAML | M5 cells 0-9 | **Abrir el YAML en pantalla** y leer juntos |
| **M5 §5 — ejecución manual + observabilidad** | 8 min | `gcloud workflows execute`, polling, pipeline_runs, mensaje en topic status | M5 cells 13-16 | Ejecutar en vivo si IAM lo permite |
| **M5 §6-§7 — Scheduler + Eventarc** | 8 min | Doble disparador, complementariedad | M5 cells 18-20 | Pizarra: línea de tiempo del mes con cron + Eventarc |
| **M5 §8 — Composer DAG (lectura)** | 5 min | Comparativa lado a lado | M5 cells 22-23 | Solo mencionar — no profundizar |
| **Integrador §2-§4 — eventos sintéticos + Function** | 10 min | LAG() para detectar transiciones, código Function embebido | Integ. cells 5-12 | **Leer el código de la Function en pantalla** — explicar filtro + invoke |
| **Integrador §6 — end-to-end run en vivo** | 10 min | Publish 18 eventos → Function filtra → Workflow corre × 3 → SPs ejecutan | Integ. cells 16-19 | **DEMO EN VIVO** si IAM lo permite. Si no, mostrar logs anteriores |
| **Findings honestos** | 7 min | AUC=0.84 sospechoso, 41% exits, sesgo country, GDPR Art. 22 | M6 cell 45, integ. cell 29 | Pizarra: lista de banderas rojas |
| **Test de conceptos** | 10 min | Quiz oral de 5 preguntas (ver §13) | — | — |
| **Feedback individual** | 5 min | 1-2 min por alumno: "qué te ha resonado, qué se te ha atascado" | — | Recoger por chat de Zoom |

**Total = 120 minutos.**

---

## 12. Demo en vivo — checklist de ejecución

### 12.1 Pre-clase (1 hora antes)

- [ ] M6 ejecutado completo. Verificar `bq ls feature_store_retention`, `bq ls predictions_retention`, `bq ls ml_models`, `bq ls pipeline_runs`.
- [ ] Modelo entrenado: `bq query "SELECT * FROM ml_models.INFORMATION_SCHEMA.MODELS"`.
- [ ] Workflow desplegado y ACTIVE: `gcloud workflows describe retention-pipeline --location=europe-southwest1`.
- [ ] Topics existen: `gcloud pubsub topics list | grep -E "hr-events|retention-pipeline"`.
- [ ] Cloud Function desplegada **(BLOQUEADO POR IAM — ver §14)**.

### 12.2 Durante la clase

#### Demo 1 — ejecución manual del Workflow (M5)
```bash
gcloud workflows execute retention-pipeline \
  --location=europe-southwest1 \
  --data='{"target_month":"2025-11-01"}'
```
Esperar 16-20 segundos. Mostrar:
```sql
SELECT step, status, rows_written, ROUND(duration_seconds, 2) AS dur_s, start_time
FROM pipeline_runs.retention_pipeline_runs
WHERE start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
ORDER BY start_time DESC;
```

Esperado: 4 filas (build_features, score, apply_decision, [snapshot]) todas SUCCESS.

#### Demo 2 — pull del topic status
```python
response = subscriber.pull(request={"subscription": ".../retention-pipeline-status-pull",
                                     "max_messages": 5})
for msg in response.received_messages:
    print(msg.message.data.decode("utf-8"), msg.message.attributes)
```
Esperado: 1 mensaje con `target_month=2025-11-01, status=SUCCESS`.

#### Demo 3 (si IAM permite) — end-to-end event-driven
```python
# Publicar 1 PAYROLL_CLOSED
publisher.publish(topic_path, json.dumps({
    "event_id": "demo-class",
    "event_type": "PAYROLL_CLOSED",
    "event_timestamp": "2025-12-01T18:00:00Z",
    "target_month": "2025-12-01",  # nuevo mes → no debería tener actions previas
    "source": "demo",
    "payload": "{}"
}).encode("utf-8"))

# Esperar 60s, mirar logs de la Function
!gcloud functions logs read event-router-retention --region=europe-southwest1 --limit=20
```

**Plan B si la Function no está desplegada:**
- Mostrar `event-router-retention/main.py` en pantalla (la celda 10 del integrador).
- Explicar el flujo verbalmente.
- Demo del Workflow standalone (Demo 1).

### 12.3 Cleanup post-clase (opcional)

```bash
# Solo si quieres limpiar los datasets de práctica
bq rm -r -f -d feature_store_retention
bq rm -r -f -d predictions_retention
bq rm -r -f -d ml_models
bq rm -r -f -d pipeline_runs

# Workflow + Scheduler + Function
gcloud workflows delete retention-pipeline --location=europe-southwest1 --quiet
gcloud scheduler jobs delete retention-pipeline-monthly --location=europe-southwest1 --quiet
gcloud functions delete event-router-retention --region=europe-southwest1 --quiet
```

---

## 13. Preguntas que harán los alumnos y respuestas

### Pregunta 1: "¿Por qué Workflows y no Airflow?"
**Respuesta corta:** $300/mes vs $0/mes. Para <10 pipelines GCP-only, Workflows gana.
**Respuesta larga:** Airflow es estándar en ecosistemas data cross-cloud (AWS+GCP+on-prem). Para People Analytics con 4-5 pipelines, Composer es overkill. Si en 12 meses crecemos a 30 pipelines o necesitamos operadores Snowflake/dbt, migramos. **Hoy, optimiza por simplicidad.**

### Pregunta 2: "¿Por qué `DELETE+INSERT` y no `MERGE`?"
**Respuesta:** `MERGE` requiere clave compuesta y es más lento porque escanea ambas tablas. `DELETE WHERE partition = target` aprovecha la partición física → casi gratis. En tablas pequeñas no se ve, pero el patrón escala.

### Pregunta 3: "¿Por qué BQML logistic y no XGBoost?"
**Respuesta:** Logistic es el baseline. Si no supera al naive, ningún modelo más complejo lo va a hacer. XGBoost añade complejidad operacional (export model, deploy en Vertex Endpoint) — solo se justifica si añade valor medible. Logistic vive **en BQ**, sin moving parts.

### Pregunta 4: "¿Y si publicamos 2 PAYROLL_CLOSED del mismo mes a la vez?"
**Respuesta:** Race condition. Idempotencia por partición protege contra duplicados, **no contra concurrencia simultánea**. En prod: singleton lock externo (Redis, Firestore con TTL) o `serializable_isolation` en el SP. Para clase, asumimos singleton publisher.

### Pregunta 5: "¿Qué pasa si Pub/Sub entrega un mensaje 2 veces?"
**Respuesta:** La Function corre el Workflow 2 veces. El Workflow llama al SP. El SP `DELETE+INSERT` por partición → mismo resultado, sin duplicados. **Idempotencia heredada en acción.**

### Pregunta 6: "¿Por qué no usamos Cloud Run Jobs en lugar de Cloud Functions?"
**Respuesta:** Functions gen2 está construido sobre Cloud Run, así que la diferencia es semántica:
- **Functions** = trigger event-driven, código corto, autoscaling fino, runtime managed.
- **Cloud Run Jobs** = batch, ejecución programada, container completo, mejor para tareas largas (>9 min de Functions).
La Function hace 1 cosa: filtrar evento + invocar Workflow. Functions encaja perfecto.

### Pregunta 7: "El AUC 0.84 me parece sospechoso, ¿es normal?"
**Respuesta:** **Sí es sospechoso.** Con 209 empleados y 41% de exits, el modelo puede estar memorizando. La validación temporal ayuda, pero la varianza con N=209 es enorme. Antes de prod: bootstrap del AUC, fairness por country, validación en datos no contaminados.

### Pregunta 8: "¿Por qué k-anonymity ≥5 y no ≥10?"
**Respuesta:** Es un trade-off. ≥10 protege más pero pierde granularidad (muchas cohortes se ocultan). ≥5 es el estándar HR de facto (en Spain LOPDGDD el "criterio de identificación razonable"). Para datasets >1000 empleados se sube a 10. Aquí con 209, ≥5 sería ya restrictivo — pero lo aplicamos porque el patrón importa.

### Pregunta 9: "¿Puedo añadir un step nuevo al Workflow sin redespegar?"
**Respuesta:** **No.** El YAML es la fuente de verdad. Cualquier cambio → `gcloud workflows deploy` → nueva versión. Las versiones anteriores se conservan (rollback en consola). En M9 (GitHub) lo automatizamos con CI/CD.

### Pregunta 10: "¿La Function escala automáticamente?"
**Respuesta:** Sí. Configuramos `--max-instances=5` → hasta 5 instancias paralelas. Cada instancia procesa 1 mensaje a la vez (Pub/Sub mantiene el ack). Si llegan 100 PAYROLL_CLOSED simultáneos, se procesan en bloques de 5. **Cuidado**: 5 Workflows simultáneos sobre 5 meses distintos = OK; 5 sobre el mismo mes = race condition.

---

## 14. Estado de validación + bloqueos IAM

### 14.1 Estado actual

| Componente | Estado | Evidencia |
|---|---|---|
| M6 SPs | ✅ Validados | `bq query "CALL ..."` ejecuta sin errores |
| Modelo BQML | ✅ Entrenado | AUC=0.84, AUC ROC=0.84 sobre hold-out |
| Tablas materializadas | ✅ Pobladas | features (1,162 filas), scores (316), retention_actions (316) |
| Snapshots auditoría | ✅ Creados | 3 snapshots `retention_actions_snapshot_YYYYMM_*` |
| M5 Workflow | ✅ ACTIVE + ejecutado | Última ejecución SUCCEEDED en ~16s, 4 pasos |
| Pub/Sub topics | ✅ Creados | `retention-pipeline-status`, `retention-pipeline-alerts`, `hr-events`, `hr-events-dlq` |
| Cloud Function | ⏳ **Bloqueado** | Falta `roles/cloudfunctions.developer` o equivalente |
| Eventarc trigger | ⏳ Pendiente | Depende de Function desplegada |
| End-to-end live run | ⏳ Pendiente IAM | Bloqueado por permisos de deploy |

### 14.2 Para destrabar — comandos exactos

```bash
PROJECT=project-9176af0b-ecb3-4050-859
SA=221134007818-compute@developer.gserviceaccount.com

for ROLE in \
  roles/logging.logWriter \
  roles/pubsub.publisher \
  roles/workflows.invoker \
  roles/cloudfunctions.invoker \
  roles/eventarc.eventReceiver; do
  gcloud projects add-iam-policy-binding $PROJECT \
    --member="serviceAccount:$SA" \
    --role=$ROLE --condition=None
done
```

Requiere `roles/owner` o `roles/resourcemanager.projectIamAdmin`.

### 14.3 Plan B si IAM no se destraba antes de la clase

1. **Demo 1 (ejecución manual del Workflow)** funciona sin nada nuevo. Es el 80% del valor pedagógico.
2. **Demo 2 (pull del topic status)** funciona sin nada nuevo.
3. **Demo 3 (end-to-end event-driven)** se sustituye por:
   - Mostrar el código de la Function en pantalla (celda 10 del integrador).
   - Explicar el flujo verbalmente con la pizarra (filtro + invoke).
   - Mostrar logs de una ejecución previa si la tienes.

El alumno entiende el **patrón** sin necesidad de ver el deploy en vivo.

---

## Resumen — qué tienen que llevarse los alumnos

1. **Idempotencia heredada** — cada capa la hereda gratis si la base la respeta.
2. **El cerebro vive en BigQuery** — SPs + UDFs + BQML, no en Python.
3. **El filtrado va en la Function**, no en el publisher.
4. **Modelo de coste explícito** (Cu/Co/τ\*) — un modelo de retención produce decisiones, no predicciones.
5. **Findings honestos no son anexo** — AUC=0.84 con N=209 es sospechoso, GDPR Art. 22 prohíbe que esto sea decisión final.
6. **Workflows > Composer** para <10 pipelines GCP-only.
7. **Doble disparador** (cron + evento) cubre los dos modos de operación.
8. **`require_partition_filter=TRUE`** es el guardarraíl que evita facturas asesinas.
9. **k-anonymity ≥5** en cualquier vista que vaya a HRBP.
10. **Snapshots delta-encoded** son baratos — úsalos por defecto.

---

**Próxima sesión (M7):** SQL avanzado aplicado a People Analytics — window functions de cohorte para enriquecer las features que entran al modelo.
