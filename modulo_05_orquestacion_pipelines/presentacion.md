# Módulo 5: Orquestación Profesional de Pipelines

## Información de la sesión
- **Sesión:** 3 (primera parte — se imparte junto con el Módulo 6)
- **Fecha:** Lunes 4 de Mayo, 2026, 16:00–18:00
- **Tiempo asignado al Módulo 5:** ~50 minutos (temas 5.1–5.5 en vivo)
- **Audiencia:** Ingenieros y analistas de datos avanzados (equipo de People Analytics)
- **Prerequisitos:** Módulos 1–4 completados. **Módulo 6 ejecutado primero** — necesitamos los Stored Procedures `sp_build_retention_features`, `sp_backfill_features` y `sp_apply_decision_rule` desplegados en BigQuery.
- **Estructura de la sesión:** Repaso → Módulo 5 (orquestación) → Módulo 6 (proyecto e2e) → Test de Conceptos → Feedback Individual

> Nota didáctica: **el orden lógico es M6 primero, M5 después**, aunque el syllabus los lista al revés. M6 construye el pipeline; M5 lo orquesta. En clase ejecutamos en ese orden.

- **Notebook práctico:** Módulo 5 notebook — despliegue de Cloud Workflows (YAML), Cloud Scheduler, Eventarc, y comparativa con Composer DAG (código). Orquesta el pipeline construido en M6.

### Temas en vivo (Sesión 3, parte 1):
| Tema | Contenido | Tiempo |
|------|-----------|--------|
| 5.1 | Orquestación: qué es y por qué la necesitamos | 8 min |
| 5.2 | Google Cloud Workflows (lightweight) | 12 min |
| 5.3 | Cloud Composer / Managed Airflow (complex) | 12 min |
| 5.4 | Comparativa Workflows vs Composer | 8 min |
| 5.5 | Integración con Eventarc y Cloud Scheduler | 10 min |

---

## Filosofía del módulo

> "El orquestador no hace el trabajo — decide **cuándo** y **en qué orden** se hace el trabajo. Si tu orquestador contiene lógica de negocio, lo estás usando mal."

En People Analytics el coste de un pipeline mal orquestado es doble:
- **Operacional:** un pipeline que falla en silencio sobre datos de nómina puede dar lugar a decisiones (bonus, ascensos, despidos) tomadas con datos obsoletos. El compliance officer va a tener preguntas.
- **Reputacional:** los HRBP pierden confianza en el dato si "el dashboard no se actualizó esta mañana" pasa más de una vez.

El proyecto del Módulo 6 produjo Stored Procedures idempotentes en BigQuery que construyen features, entrenan modelos y aplican reglas de decisión. **M5 los orquesta** — los conecta en un flujo, los lanza en el momento correcto y reacciona a fallos.

---

## Tema 5.1: Orquestación — qué es y por qué la necesitamos

### Conceptos clave
- **Orquestación** = coordinar la ejecución de **múltiples pasos**, cada uno con sus dependencias, reintentos, alertas, y manejo de errores.
- Distinción esencial frente a **scripting**:
  - Un script bash con `bq query ... && bq query ...` "funciona" hasta que falla un paso intermedio. ¿Reintentar? ¿Notificar? ¿Reanudar desde el paso 3? Un script no responde a esto.
  - Un orquestador sí: define explícitamente la topología de pasos (DAG), políticas de reintento, dependencias, eventos disparadores.
- En GCP hay tres familias de orquestadores, ordenadas por complejidad:
  1. **Cloud Scheduler** — solo cron simple ("ejecuta esto cada lunes a las 6").
  2. **Cloud Workflows** — flujo declarativo en YAML, ligero, serverless, integra nativamente con APIs de GCP.
  3. **Cloud Composer / Managed Airflow** — orquestación compleja con DAGs en Python, ecosystem de operators, UI rica.

### Detalle técnico

**¿Por qué no orquestar desde Python en una VM?**

| Aspecto | VM con cron | Cloud Workflows | Cloud Composer |
|---------|-------------|-----------------|----------------|
| Mantenimiento de la VM | Tu equipo | GCP | GCP |
| Coste cuando no corre | Sí (VM encendida) | 0 | Sí (cluster GKE encendido ~$0.50/h) |
| Reintentos automáticos | No | Sí (config) | Sí (config) |
| UI de visualización | No | Básica | Rica (Airflow UI) |
| Logs centralizados | Configurar | Cloud Logging | Cloud Logging + Airflow logs |
| Estado entre ejecuciones | No | No | Sí (XCom) |
| Curva de aprendizaje | Baja | Baja | Media-alta |
| Despliegue | SSH + edit | `gcloud workflows deploy` | Subir DAG a GCS bucket |

**Anti-patrón frecuente:** "tenemos un cron en la VM de analítica que corre cada hora un script que recarga BigQuery". Funciona hasta el día que la VM tiene un kernel update, falla el cron, nadie se entera, y el dashboard del CHRO muestra datos del lunes anterior durante 3 días.

### Aplicación en People Analytics
- **Caso del proyecto:** el pipeline de retention risk tiene 4 pasos: build_features → train_model → score → apply_decision. Si falla el modelo entrenamiento (datos insuficientes ese mes), no debemos seguir y aplicar decisiones con un modelo viejo silenciosamente — el orquestador debe parar y avisar.
- **Patrón recomendado:** empezar siempre con Cloud Workflows. Subir a Composer solo cuando tienes >10 pipelines interdependientes o necesitas operators específicos de Airflow (Snowflake, dbt, Sagemaker).

---

## Tema 5.2: Cloud Workflows (lightweight)

### Conceptos clave
- **Cloud Workflows** ejecuta flujos definidos en **YAML** que invocan HTTP endpoints o servicios de GCP.
- Es **serverless** y se factura por step ejecutado (~$0.01 por 1000 steps internos, ~$0.025 por 1000 calls externos). Para un pipeline mensual de PA: céntimos al mes.
- Diseñado para flujos **lineales o moderadamente ramificados** (hasta ~30 pasos). Si tu flujo tiene 50+ pasos con dependencias complejas, es señal de que necesitas Composer.

### Detalle técnico

**Estructura de un Workflow YAML:**

```yaml
main:
  params: [args]
  steps:
    - log_inicio:
        call: sys.log
        args:
          text: "Pipeline retention iniciado"

    - obtener_mes_target:
        assign:
          - target_month: ${default(args.target_month, text.format("%s-01", time.format(sys.now(), "%Y-%m")))}

    - paso_1_build_features:
        call: googleapis.bigquery.v2.jobs.query
        args:
          projectId: ${sys.get_env("GOOGLE_CLOUD_PROJECT")}
          body:
            query: ${"CALL `feature_store_retention.sp_build_retention_features`(DATE '" + target_month + "')"}
            useLegacySql: false
            labels:
              pipeline: retention-risk
              step: build_features
        retry:
          predicate: ${http.default_retry_predicate}
          max_retries: 3
          backoff:
            initial_delay: 10
            multiplier: 2

    - paso_2_score:
        call: googleapis.bigquery.v2.jobs.query
        args:
          projectId: ${sys.get_env("GOOGLE_CLOUD_PROJECT")}
          body:
            query: ${"CALL `predictions_retention.sp_score_retention`(DATE '" + target_month + "')"}
            labels:
              pipeline: retention-risk
              step: score

    - paso_3_apply_decision:
        call: googleapis.bigquery.v2.jobs.query
        args:
          projectId: ${sys.get_env("GOOGLE_CLOUD_PROJECT")}
          body:
            query: ${"CALL `predictions_retention.sp_apply_decision_rule`(DATE '" + target_month + "')"}
            labels:
              pipeline: retention-risk
              step: apply_decision

    - notificar_exito:
        call: googleapis.pubsub.v1.projects.topics.publish
        args:
          topic: ${"projects/" + sys.get_env("GOOGLE_CLOUD_PROJECT") + "/topics/retention-pipeline-status"}
          body:
            messages:
              - data: ${base64.encode(text.encode("Pipeline retention OK para " + target_month))}

    - return_status:
        return:
          status: SUCCESS
          target_month: ${target_month}
```

**Despliegue (idempotente):**

```bash
gcloud workflows deploy retention-pipeline \
  --location=europe-southwest1 \
  --source=workflows/retention_pipeline.yaml \
  --service-account=sa-workflows@PROJECT_ID.iam.gserviceaccount.com \
  --description="Pipeline mensual de retention risk — orquesta SPs de feature_store_retention y predictions_retention"
```

**Ejecución manual:**

```bash
gcloud workflows execute retention-pipeline \
  --location=europe-southwest1 \
  --data='{"target_month":"2025-11-01"}'
```

**Manejo de errores con `try/except`:**

```yaml
- paso_1_build_features:
    try:
      call: googleapis.bigquery.v2.jobs.query
      args: ...
    except:
      as: e
      steps:
        - log_error:
            call: sys.log
            args:
              text: ${"Falló build_features: " + e.message}
              severity: ERROR
        - notificar_fallo:
            call: googleapis.pubsub.v1.projects.topics.publish
            args:
              topic: ${"projects/" + sys.get_env("GOOGLE_CLOUD_PROJECT") + "/topics/retention-pipeline-alerts"}
              body:
                messages:
                  - data: ${base64.encode(text.encode("ERROR build_features: " + e.message))}
        - raise:
            raise: ${e}
```

### Aplicación en People Analytics
- **Caso del proyecto:** el `workflows/retention_pipeline.yaml` lo desplegamos en el notebook de M5 y lo lanzamos manualmente para snapshot 2025-11. Verificamos que escribe en `pipeline_runs`, que produce filas en `retention_actions`, y que envía mensaje a Pub/Sub.
- **Buena práctica:** un Workflow por **dominio funcional**. No hagas un mega-Workflow que haga todo el data warehouse de PA — fragmentalo en flujos de retention, headcount, compensation, etc.

---

## Tema 5.3: Cloud Composer / Managed Airflow

### Conceptos clave
- **Cloud Composer** = Apache Airflow gestionado por GCP. Corre sobre un cluster GKE.
- DAGs definidos en **Python** (mucho más expresivo que YAML para lógica compleja).
- Ecosystem masivo de **operators**: BigQueryInsertJobOperator, GCSToBigQueryOperator, SlackAPIOperator, KubernetesPodOperator, dbtCloudRunJobOperator, etc.
- **Coste de entrada alto**: cluster mínimo ~$300/mes. No tiene sentido para 1-2 pipelines.

### Detalle técnico

**Equivalente Airflow del Workflow anterior:**

```python
# composer/retention_pipeline_dag.py
from airflow import DAG
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from airflow.providers.google.cloud.operators.pubsub import PubSubPublishMessageOperator
from datetime import datetime, timedelta
import base64

default_args = {
    "owner": "people-analytics",
    "depends_on_past": False,
    "email_on_failure": True,
    "email": ["data-eng-team@imagina.es"],
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "labels": {"pipeline": "retention-risk", "team": "people-analytics"},
}

with DAG(
    dag_id="retention_pipeline",
    default_args=default_args,
    description="Pipeline mensual de retention risk",
    schedule_interval="0 6 1 * *",     # día 1 de cada mes a las 06:00
    start_date=datetime(2025, 1, 1),
    catchup=False,                      # no backfill automático
    max_active_runs=1,
    tags=["people-analytics", "retention", "monthly"],
) as dag:

    target_month = "{{ macros.ds_format(macros.ds_add(ds, -macros.ds_format(ds, '%d')|int + 1), '%Y-%m-%d', '%Y-%m-%d') }}"

    build_features = BigQueryInsertJobOperator(
        task_id="build_features",
        configuration={
            "query": {
                "query": f"CALL `feature_store_retention.sp_build_retention_features`(DATE '{target_month}')",
                "useLegacySql": False,
            },
            "labels": {"pipeline": "retention-risk", "step": "build_features"},
        },
        location="europe-southwest1",
    )

    score = BigQueryInsertJobOperator(
        task_id="score",
        configuration={
            "query": {
                "query": f"CALL `predictions_retention.sp_score_retention`(DATE '{target_month}')",
                "useLegacySql": False,
            },
        },
        location="europe-southwest1",
    )

    apply_decision = BigQueryInsertJobOperator(
        task_id="apply_decision",
        configuration={
            "query": {
                "query": f"CALL `predictions_retention.sp_apply_decision_rule`(DATE '{target_month}')",
                "useLegacySql": False,
            },
        },
        location="europe-southwest1",
    )

    notify_success = PubSubPublishMessageOperator(
        task_id="notify_success",
        project_id="people-analytics-formacion",
        topic="retention-pipeline-status",
        messages=[{"data": base64.b64encode(b"Pipeline retention OK")}],
    )

    build_features >> score >> apply_decision >> notify_success
```

**Despliegue:** subir el `.py` al bucket GCS de DAGs del entorno Composer:

```bash
gcloud composer environments storage dags import \
  --environment=people-analytics-prod \
  --location=europe-southwest1 \
  --source=composer/retention_pipeline_dag.py
```

### Cuándo Composer aporta valor real

1. **Más de 10 DAGs interconectados** con dependencias cruzadas (ExternalTaskSensor).
2. **Operadores específicos** que Workflows no tiene: dbt Cloud, Snowflake, Databricks, Slack notifier rico, Datadog metrics.
3. **Ramificación dinámica** (TaskFlow API, dynamic task mapping).
4. **Integración con un CI/CD ya basado en GitHub Actions + Airflow**.

### Aplicación en People Analytics
- **Decisión típica del cliente:** "¿migramos a Composer?". Respuesta honesta: **solo si ya pasáis los $300/mes en otro lado** (data warehouse de marketing, ML platform, etc). Para un equipo de PA con 3-5 pipelines, Workflows + Scheduler bastan.
- **Compatibilidad con Dataform (M8):** Dataform tiene su propio scheduler (releases + workflows). Si todo tu data ya vive en Dataform, ni Workflows ni Composer son necesarios para los pipelines BQ → BQ.

---

## Tema 5.4: Comparativa Workflows vs Composer

### Tabla de decisión

| Pregunta | Si la respuesta es "sí"... |
|----------|---------------------------|
| ¿Tienes <10 pipelines y todos viven en GCP? | **Workflows** |
| ¿Necesitas operators de terceros (dbt, Snowflake, Slack rich)? | **Composer** |
| ¿Quieres pagar 0€ cuando no hay ejecuciones? | **Workflows** |
| ¿Vas a tener pipelines con >30 pasos o ramificación compleja? | **Composer** |
| ¿Tu equipo ya conoce Airflow? | **Composer** (curva mínima) |
| ¿El equipo es nuevo en orquestación? | **Workflows** (curva más suave) |
| ¿Necesitas backfills históricos automáticos? | **Composer** (`catchup=True`) |
| ¿El pipeline debe ser puramente event-driven? | **Workflows + Eventarc** |
| ¿Sensible al coste mensual fijo? | **Workflows** |

### Patrón híbrido (avanzado)

Cuando en una empresa hay ambos: **Composer** para pipelines complejos cross-system; **Workflows** para flujos puntuales y reactivos a eventos. Composer puede llamar a Workflows como un step más (HttpOperator), e incluso Eventarc puede disparar Workflows que luego invoquen DAGs de Composer si hace falta.

### Aplicación en People Analytics
- **Recomendación inicial para el cliente:** Workflows para todo el data warehouse de PA. Reevaluar a los 6 meses si han aparecido casos de uso que justifiquen Composer.
- **Anti-patrón:** desplegar Composer "por si acaso lo necesitamos en el futuro". El cluster te factura aunque no haya DAGs ejecutándose.

---

## Tema 5.5: Integración con Eventarc y Cloud Scheduler

### Conceptos clave
- Un orquestador no se ejecuta solo — necesita un **trigger** (qué evento lo lanza).
- Tres tipos de triggers en GCP:
  1. **Manual** (`gcloud workflows execute`) — para testing.
  2. **Programado** (Cloud Scheduler) — para cadencias fijas: "día 1 de cada mes a las 06:00".
  3. **Event-driven** (Eventarc) — para reaccionar a eventos: "cuando llegue el fichero de payroll a GCS".

### Detalle técnico

**Cloud Scheduler — cron mensual:**

```bash
# Job que dispara el Workflow el día 1 de cada mes a las 06:00 (Madrid time)
gcloud scheduler jobs create http retention-pipeline-monthly \
  --location=europe-southwest1 \
  --schedule="0 6 1 * *" \
  --time-zone="Europe/Madrid" \
  --uri="https://workflowexecutions.googleapis.com/v1/projects/PROJECT_ID/locations/europe-southwest1/workflows/retention-pipeline/executions" \
  --http-method=POST \
  --oauth-service-account-email="sa-scheduler@PROJECT_ID.iam.gserviceaccount.com" \
  --headers="Content-Type=application/json" \
  --message-body='{"argument":"{\"target_month\":\"auto\"}"}'
```

**Eventarc — disparar al landing de payroll en GCS:**

```bash
# Trigger: cuando aparece un .csv en gs://datalake/payroll/incoming/
gcloud eventarc triggers create retention-on-payroll-arrival \
  --location=europe-southwest1 \
  --destination-workflow=retention-pipeline \
  --destination-workflow-location=europe-southwest1 \
  --event-filters="type=google.cloud.storage.object.v1.finalized" \
  --event-filters="bucket=PROJECT_ID-datalake" \
  --event-filters-path-pattern="name=payroll/incoming/payroll_*.csv" \
  --service-account="sa-eventarc@PROJECT_ID.iam.gserviceaccount.com"
```

**Combinación de los dos triggers — el patrón de producción:**

```
[Cloud Scheduler: día 1 de mes 06:00] ──┐
                                         ├──→ [Cloud Workflows: retention-pipeline] ──→ [Stored Procs en BQ]
[Eventarc: payroll_*.csv en GCS]   ─────┘                  │
                                                            ├──→ [Pub/Sub: éxito]
                                                            │      └──→ [Slack notifier]
                                                            └──→ [Pub/Sub: fallo]
                                                                   └──→ [PagerDuty / email DPO]
```

Las dos rutas convergen en el mismo Workflow, que es **idempotente** (gracias a los SPs de M6) — si por casualidad ambos disparadores se activan simultáneamente, no rompemos datos.

### Buenas prácticas para pipelines resilientes (recap de M4 aplicado a M5)

1. **Idempotencia heredada del SP**: el orquestador puede reintentar sin miedo. Si un step falla a mitad, re-ejecutar produce el mismo resultado.
2. **Reintentos con backoff exponencial**: definidos en el YAML del Workflow o `retry_delay` del DAG.
3. **Alertas en fallo, no solo en éxito**: Pub/Sub a un topic `*-alerts` separado, con suscriptor que notifique a Slack/email.
4. **Logs estructurados**: cada step loguea con `severity` y campos JSON para que Cloud Logging los pueda consultar.
5. **Métricas de pipeline**: tabla `pipeline_runs.retention_pipeline_runs` (ya creada en M6) capturando duración, filas, errores. En M17 añadiremos sinks a Cloud Logging.
6. **Una sola "fuente de verdad" de la lógica**: la lógica vive en los SPs de BigQuery. El orquestador solo decide *cuándo*. Si tienes lógica de negocio en el YAML del Workflow, refactorízala a un SP.

### Aplicación en People Analytics
- **Caso del proyecto:** desplegamos Scheduler + Eventarc en el notebook de M5. Lo importante es **mostrar las dos opciones** para que el alumno entienda cuándo usar cada una.
- **Pregunta abierta para el cliente:** ¿el pipeline mensual debe correr el día 1 (data del mes cerrado) o el día 5 (cuando nómina ya cerró su procesamiento)? Es una decisión de negocio, no técnica — Cloud Scheduler permite cualquier cron.

---

## Cierre del Módulo 5

### Lo que el alumno se lleva
- Orquestación es **decidir cuándo y en qué orden**, no hacer trabajo. La lógica vive en los SPs (M6) y en Dataform (M8).
- **Workflows primero, Composer cuando duela**. La curva de coste/complejidad de Composer no se justifica para pocos pipelines.
- **Scheduler + Eventarc** son complementarios — usa los dos cuando tu pipeline debe correr tanto periódicamente como reactivamente.
- La **idempotencia es responsabilidad del SP**, no del orquestador. Esto separa cleanly responsabilidades.

### Conexión con el proyecto e2e
El notebook de M5 toma los SPs construidos en M6 y los conecta en un Workflow + Scheduler + Eventarc. Es **el mismo pipeline**, expuesto a través de la capa de orquestación. El alumno ve cómo **una buena arquitectura del WAREHOUSE (M6) facilita una orquestación trivial (M5)**.

### Conexión con módulos siguientes
- **M8 (Dataform)** versionará los SPs y reemplazará parte de la orquestación con sus releases.
- **M9 (GitHub)** versionará el YAML del Workflow y el DAG de Composer.
- **M10 (Backups)** añadirá un step de snapshot al inicio del Workflow.
- **M17 (Observabilidad)** integrará Cloud Logging + Monitoring para alertas richer.

### Test de conceptos (preguntas tipo)
1. ¿Cuándo elegirías Workflows sobre Composer? Da 3 razones concretas.
2. ¿Por qué la idempotencia debe vivir en el SP y no en el orquestador?
3. ¿Cuál es la diferencia entre Cloud Scheduler y Eventarc? ¿Pueden coexistir?
4. ¿Qué pasa si un step de un Workflow falla por el cuarto reintento? ¿Cómo se propaga la alerta?
5. Si tu equipo de PA tiene 3 pipelines y un budget de $50/mes en orquestación, ¿qué eliges?
6. ¿Dónde debería estar el SQL del CALL: en el YAML del Workflow o en un Stored Procedure? ¿Por qué?

### Recursos
- [Cloud Workflows docs](https://cloud.google.com/workflows/docs)
- [Workflows YAML syntax reference](https://cloud.google.com/workflows/docs/reference/syntax)
- [Cloud Composer / Apache Airflow](https://cloud.google.com/composer/docs)
- [Eventarc triggers](https://cloud.google.com/eventarc/docs/creating-triggers)
- [Cloud Scheduler cron jobs](https://cloud.google.com/scheduler/docs)
- [Workflows vs Composer decision guide](https://cloud.google.com/workflows/docs/comparison)
