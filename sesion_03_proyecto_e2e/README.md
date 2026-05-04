# Sesión 3 — Proyecto end-to-end

Pipeline event-driven de **Retention Risk** que conecta los 4 módulos previos (M3 + M4 + M5 + M6) sobre datos reales anonimizados de Personio.

## Arquitectura completa

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Datos reales Personio (M1+M2)                                               │
│  silver_personio.fact_salary_history  +  silver_personio.dim_employee        │
└────────────────┬─────────────────────────────────────────────────────────────┘
                 │ detecta transiciones reales (altas, bajas, cambios salario)
                 ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  Módulo 3 — Bus de eventos                                                   │
│  Topic Pub/Sub  hr-events  +  pull subscription auditing                     │
│  (eventos: PAYROLL_CLOSED, EMPLOYEE_HIRED, EMPLOYEE_TERMINATED, …)           │
└────────────────┬─────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  Cloud Function gen2  event-router-retention   (NUEVO en sesión 3)           │
│  Filtra: solo PAYROLL_CLOSED dispara → invoca Workflow con target_month      │
│  Sigue patrón M4: structured logging, retry implícito, DLQ disponible        │
└────────────────┬─────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  Módulo 5 — Cloud Workflows  retention-pipeline                              │
│  4 pasos: build_features → score → apply_decision → snapshot                 │
└────────────────┬─────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  Módulo 6 — Stored Procedures + UDFs + BQML                                  │
│  feature_store_retention.features  →  ml_models.retention_logistic_v1        │
│  →  predictions_retention.scores  →  predictions_retention.retention_actions │
└────────────────┬─────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  Output final  predictions_retention.retention_actions                       │
│  + Snapshots inmutables  retention_actions_snapshot_YYYYMMDD                 │
│  + Log de runs  pipeline_runs.retention_pipeline_runs                        │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Orden de ejecución

```
1. modulo_01_contexto_people_analytics/notebook.ipynb        ← M1+M2: Bronze→Silver→Gold
2. modulo_02_arquitectura_gcp/notebook.ipynb                 ← (parte de la sesión 1)
3. modulo_03_ingesta_datos/notebook.ipynb                    ← M3: bus hr-events
4. modulo_04_pipelines_eventos/notebook.ipynb                ← M4: event-driven patterns
5. modulo_06_bigquery_buenas_practicas/notebook.ipynb        ← M6: SPs, UDFs, BQML, decisión newsvendor
6. modulo_05_orquestacion_pipelines/notebook.ipynb           ← M5: Workflow + Scheduler + Eventarc
7. sesion_03_proyecto_e2e/notebook.ipynb                     ← Integrador: Function + end-to-end run
```

> Nota: M6 antes de M5 porque M5 orquesta los SPs construidos en M6.

## Permisos necesarios (IAM)

### A nivel de dataset (asignables con `roles/editor`, sin necesidad de IAM admin)

La cuenta o Service Account que ejecuta el pipeline necesita acceso a los siguientes datasets:

| Dataset | Rol mínimo |
|---|---|
| `silver_personio` | READER |
| `gold_people_analytics` | READER |
| `feature_store_retention` | WRITER |
| `predictions_retention` | WRITER |
| `pipeline_runs` | WRITER |
| `ml_models` | WRITER |

```python
from google.cloud import bigquery
client = bigquery.Client(project=PROJECT)
SA = "221134007818-compute@developer.gserviceaccount.com"  # o tu SA
for ds_name, role in [
    ("silver_personio", "READER"),
    ("gold_people_analytics", "READER"),
    ("feature_store_retention", "WRITER"),
    ("predictions_retention", "WRITER"),
    ("pipeline_runs", "WRITER"),
    ("ml_models", "WRITER"),
]:
    ds = client.get_dataset(f"{PROJECT}.{ds_name}")
    entries = [e for e in ds.access_entries if not (e.entity_type == "userByEmail" and e.entity_id == SA)]
    entries.append(bigquery.AccessEntry(role=role, entity_type="userByEmail", entity_id=SA))
    ds.access_entries = entries
    client.update_dataset(ds, ["access_entries"])
```

### A nivel de proyecto (requiere `roles/owner` o `resourcemanager.projectIamAdmin`)

Para ejecutar la **Cloud Function `event-router-retention`** (notebook integrador) y para activar **observabilidad completa** (sys.log + Pub/Sub publish en el Workflow), la Service Account necesita:

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

Sin esos roles, el **Workflow simplificado funciona** (sin sys.log ni Pub/Sub publish) pero la **Cloud Function no se puede desplegar** y por tanto el flujo event-driven completo no se cierra automáticamente.

## Estado de validación end-to-end

| Componente | Estado | Evidencia |
|---|---|---|
| M6 SPs (`sp_build_retention_features`, `sp_score_retention`, `sp_apply_decision_rule`) | ✅ Validados | Ejecutados directamente con `bq query CALL …` |
| Modelo BQML `retention_logistic_v1` | ✅ Entrenado | AUC ROC = 0.84 sobre hold-out (2025-09 a 2025-11) |
| Tablas materializadas | ✅ Pobladas | `features` (1,162 filas), `scores` (316), `retention_actions` (316) |
| Snapshots de auditoría | ✅ Creados | 3 snapshots `retention_actions_snapshot_YYYYMM_*` |
| M5 Workflow `retention-pipeline` | ✅ ACTIVE + ejecutado | Última ejecución: SUCCEEDED en ~16 segundos, 4 pasos |
| Topics Pub/Sub | ✅ Creados | `retention-pipeline-status`, `retention-pipeline-alerts` |
| Cloud Function `event-router-retention` | ⏳ Código listo, deploy pendiente | Falta `roles/cloudfunctions.developer` o equivalente |
| Eventarc trigger | ⏳ Pendiente | Depende de Function desplegada |
| End-to-end run (publicar evento → Function → Workflow → SPs) | ⏳ Pendiente IAM | Bloqueado por permisos de Function deploy |

## Estructura de ficheros

```
sesion_03_proyecto_e2e/
├── README.md          ← este fichero
└── notebook.ipynb     ← integrador, 30 cells, código de la Cloud Function embebido
```

El notebook es **autocontenido**: el código Python de la Cloud Function vive como string dentro de una celda, se escribe a `/tmp/cf_event_router/main.py` y se despliega con `gcloud functions deploy`. Patrón Workbench.

## Findings honestos (resumen del § 11 del notebook)

- **Backend funciona**: 109 empleados scored y decididos por mes, AUC=0.84 (sospechosamente alto para 209 empleados — probable overfitting; auditar antes de prod).
- **Idempotencia heredada**: re-ejecutar el Workflow para el mismo mes reescribe limpiamente las particiones.
- **Race conditions**: dos Workflows en paralelo sobre el MISMO mes producen último-gana. En prod usar singleton lock o `serializable_isolation` en SP.
- **No exactly-once**: Pub/Sub es at-least-once. Si la Function muere entre `CALL SP` y ack, el Workflow corre 2 veces. Idempotencia del SP nos cubre.
- **Cold start Function gen2**: ~3-5s primera invocación. Para latencia crítica, `min-instances=1`.
- **41% tasa de exits voluntarios** en este dataset (~86 de 209) es sospechosa. Probable downsizing o snapshot histórico — validar con cliente antes de poner el modelo en producción.

## Para revisión manual del instructor

1. **M6 ejecutado completamente** — abrir `modulo_06_bigquery_buenas_practicas/notebook.ipynb` en Workbench, "Run All", verificar AUC y plot final.
2. **M5 deployed** — verificar en consola GCP → Workflows → `retention-pipeline` que está ACTIVE.
3. **Integrador (este folder)** — abrir el notebook y revisar que el código de la Cloud Function tiene sentido. Cuando el admin asigne los roles IAM listados arriba, ejecutar las celdas de "End-to-end run en vivo" (sección 6) debería triggerizar todo.
4. **Cleanup** — los datasets `feature_store_retention`, `predictions_retention`, `ml_models`, `pipeline_runs` se pueden borrar al final de la sesión con `bq rm -r -d <dataset>`.
