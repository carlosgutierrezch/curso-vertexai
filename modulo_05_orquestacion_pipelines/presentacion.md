# Módulo 5: Orquestación Profesional de Pipelines

## Información de la sesión
- **Sesión:** 4
- **Fecha:** Lunes 4 de Mayo, 16:00–18:00
- **Duración:** 2 horas (sesión completa)
- **Prerequisitos:** Módulos 1–4 completados

---

## Tema 5.1: Conceptos de orquestación de flujos de datos

### Conceptos clave
- **Orquestación** es la coordinación automática de múltiples tareas que forman un pipeline de datos, gestionando dependencias, orden de ejecución, reintentos y notificaciones.
- Un **DAG** (Directed Acyclic Graph) es la estructura que define qué tareas dependen de cuáles.
- Sin orquestación, los pipelines de PA dependen de scripts manuales o crons frágiles sin gestión de errores.

### Detalle técnico

**¿Por qué orquestar?**

| Sin orquestación | Con orquestación |
|-------------------|-------------------|
| `crontab` con scripts sueltos | DAG con dependencias explícitas |
| Si falla un paso, nadie se entera | Alertas automáticas y retry |
| No hay visibilidad del estado | Dashboard con estado de cada tarea |
| Re-ejecutar requiere intervención manual | Re-ejecución con un clic / API |
| Sin control de concurrencia | Límites de paralelismo configurables |

**DAG de un pipeline típico de People Analytics:**

```
                    ┌─────────────────┐
                    │  extraer_hris   │ (Task 1)
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  validar_datos  │ (Task 2)
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼──────┐ ┌────▼─────┐ ┌──────▼───────┐
     │cargar_bronze  │ │cargar_   │ │cargar_       │ (Task 3a/b/c)
     │_empleados     │ │bronze_   │ │bronze_       │
     │               │ │nomina    │ │evaluaciones  │
     └────────┬──────┘ └────┬─────┘ └──────┬───────┘
              │              │              │
              └──────────────┼──────────────┘
                             │
                    ┌────────▼────────┐
                    │  dataform_run   │ (Task 4)
                    │ bronze→silver→  │
                    │     gold        │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼──────┐ ┌────▼─────┐ ┌──────▼───────┐
     │test_calidad   │ │refresh_  │ │notificar_    │ (Task 5a/b/c)
     │_datos         │ │looker    │ │rrhh          │
     └───────────────┘ └──────────┘ └──────────────┘
```

**Opciones de orquestación en GCP:**

| Herramienta | Tipo | Complejidad | Coste | Ideal para |
|-------------|------|-------------|-------|-----------|
| **Cloud Scheduler + Functions** | Cron simple | Baja | ~$0/mes | 1-3 tareas secuenciales |
| **Cloud Workflows** | Orquestación serverless | Media | ~$0.01/1000 ejecuciones | 5-15 pasos, lógica condicional |
| **Cloud Composer** | Managed Airflow | Alta | ~$300-500/mes (entorno mínimo) | DAGs complejos, >20 tareas, equipo grande |
| **Dataform** | Orquestación SQL | Baja | Incluido en BQ | Solo transformaciones SQL en BigQuery |

### Aplicación en People Analytics
- **Equipo pequeño (1-3 personas)**: Cloud Scheduler + Cloud Functions es suficiente.
- **Equipo medio (3-8 personas)**: Cloud Workflows para pipelines de ingesta + Dataform para transformaciones.
- **Equipo grande (>8 personas)**: Cloud Composer para orquestación central + Dataform para SQL.

---

## Tema 5.2: Google Cloud Workflows para automatizaciones ligeras

### Conceptos clave
- **Cloud Workflows** es un servicio serverless que ejecuta flujos de trabajo definidos en **YAML** o **JSON**.
- No requiere servidores, escala automáticamente y cobra por ejecución (~$0.01/1000 pasos).
- Ideal para orquestar llamadas a APIs de GCP (BigQuery, Cloud Functions, GCS) con lógica condicional y manejo de errores.

### Detalle técnico

**Workflow YAML para ETL diario de People Analytics:**

```yaml
# workflow_etl_diario.yaml
# Pipeline: extraer HRIS → cargar Bronze → ejecutar Dataform → notificar
main:
  params: [args]
  steps:
    # Paso 1: Determinar la fecha a procesar
    - init:
        assign:
          - project_id: "pa-prod"
          - fecha: ${default(map.get(args, "fecha"), text.substring(time.format(sys.now()), 0, 10))}
          - dataset: "people_analytics"

    # Paso 2: Ejecutar Cloud Function de ingesta
    - extraer_hris:
        call: http.post
        args:
          url: https://europe-west1-pa-prod.cloudfunctions.net/ingestar-hris
          auth:
            type: OIDC
          body:
            fecha: ${fecha}
          timeout: 300  # 5 minutos
        result: resultado_ingesta
    
    # Paso 3: Verificar resultado de ingesta
    - verificar_ingesta:
        switch:
          - condition: ${resultado_ingesta.body.registros == 0}
            steps:
              - log_sin_datos:
                  call: sys.log
                  args:
                    text: ${"Sin datos nuevos para " + fecha + ". Terminando."}
                    severity: "WARNING"
              - terminar_sin_datos:
                  return: "Sin datos nuevos"
    
    # Paso 4: Ejecutar Dataform (Bronze → Silver → Gold)
    - ejecutar_dataform:
        call: http.post
        args:
          url: ${"https://dataform.googleapis.com/v1beta1/projects/" + project_id + "/locations/europe-west1/repositories/people-analytics/compilationResults"}
          auth:
            type: OAuth2
          body:
            gitCommitish: "main"
        result: compilation_result
    
    # Paso 5: Verificar calidad de datos
    - test_calidad:
        call: http.post
        args:
          url: https://europe-west1-pa-prod.cloudfunctions.net/test-calidad-datos
          auth:
            type: OIDC
          body:
            fecha: ${fecha}
            dataset: ${dataset}
        result: calidad
    
    # Paso 6: Notificar resultado
    - notificar:
        switch:
          - condition: ${calidad.body.passed == true}
            steps:
              - notificar_exito:
                  call: http.post
                  args:
                    url: https://hooks.slack.com/services/T.../B.../xxx
                    body:
                      text: ${"ETL People Analytics completado para " + fecha + ". Registros: " + string(resultado_ingesta.body.registros)}
          - condition: ${calidad.body.passed == false}
            steps:
              - notificar_error_calidad:
                  call: http.post
                  args:
                    url: https://hooks.slack.com/services/T.../B.../xxx
                    body:
                      text: ${"ALERTA: Tests de calidad fallaron para " + fecha + ". Errores: " + calidad.body.errors}
    
    # Paso 7: Retornar resultado
    - finalizar:
        return:
          status: "completado"
          fecha: ${fecha}
          registros: ${resultado_ingesta.body.registros}
          calidad: ${calidad.body.passed}
```

**Desplegar y ejecutar el workflow:**

```bash
# Desplegar
gcloud workflows deploy etl-diario-pa \
    --location=europe-west1 \
    --source=workflow_etl_diario.yaml \
    --service-account=sa-workflows@pa-prod.iam.gserviceaccount.com

# Ejecutar manualmente
gcloud workflows run etl-diario-pa \
    --location=europe-west1 \
    --data='{"fecha": "2026-05-04"}'

# Ver ejecuciones
gcloud workflows executions list etl-diario-pa \
    --location=europe-west1 \
    --limit=10
```

**Manejo de errores en Workflows:**

```yaml
# Bloque try/except en Workflows
- paso_con_retry:
    try:
      call: http.post
      args:
        url: https://api.example.com/datos
        timeout: 60
      result: response
    retry:
      predicate: ${default(map.get(response, "code"), 0) >= 500}
      max_retries: 3
      backoff:
        initial_delay: 2
        max_delay: 60
        multiplier: 2
    except:
      as: e
      steps:
        - log_error:
            call: sys.log
            args:
              text: ${"Error en paso: " + json.encode_to_string(e)}
              severity: "ERROR"
        - raise_error:
            raise: ${e}
```

### Aplicación en People Analytics
- Workflow para **ETL diario**: extraer → cargar → transformar → validar → notificar.
- Workflow para **proceso mensual de nómina**: recibir archivo → validar estructura → cargar → recalcular brecha salarial → generar informe.
- Workflow para **encuesta de clima**: cerrar campaña → procesar respuestas → calcular scores → generar dashboard → enviar resumen a dirección.

---

## Tema 5.3: Cloud Composer (Managed Airflow) para pipelines complejos

### Conceptos clave
- **Cloud Composer** es Apache Airflow gestionado por Google. Airflow es el estándar de facto para orquestación de datos.
- Los pipelines se definen como **DAGs** (Directed Acyclic Graphs) en **Python**.
- Más potente que Workflows pero significativamente más costoso y complejo.

### Detalle técnico

**DAG de Airflow para ETL de People Analytics:**

```python
# dags/etl_people_analytics.py
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.google.cloud.operators.bigquery import (
    BigQueryInsertJobOperator,
    BigQueryCheckOperator,
)
from airflow.providers.google.cloud.transfers.gcs_to_bigquery import GCSToBigQueryOperator
from airflow.providers.google.cloud.operators.dataform import (
    DataformCreateCompilationResultOperator,
    DataformCreateWorkflowInvocationOperator,
)
from airflow.utils.dates import days_ago
from datetime import timedelta

default_args = {
    "owner": "people-analytics-team",
    "depends_on_past": False,
    "email": ["pa-alerts@empresa.com"],
    "email_on_failure": True,
    "email_on_retry": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="etl_people_analytics_diario",
    default_args=default_args,
    description="Pipeline ETL diario de People Analytics",
    schedule_interval="0 7 * * *",  # Cada día a las 07:00 UTC
    start_date=days_ago(1),
    catchup=False,
    tags=["people-analytics", "etl", "producción"],
) as dag:

    # Task 1: Extraer datos del HRIS
    extraer_hris = PythonOperator(
        task_id="extraer_hris",
        python_callable=extraer_datos_hris,  # Función definida en módulo de ingesta
        op_kwargs={"fecha": "{{ ds }}"},      # ds = fecha de ejecución del DAG
    )
    
    # Task 2: Cargar CSV de GCS a BigQuery (Bronze)
    cargar_bronze = GCSToBigQueryOperator(
        task_id="cargar_bronze_empleados",
        bucket="pa-datalake",
        source_objects=["hris/raw/{{ ds }}/empleados.csv"],
        destination_project_dataset_table="pa-prod.people_analytics.bronze_empleados",
        write_disposition="WRITE_TRUNCATE",
        skip_leading_rows=1,
        source_format="CSV",
    )
    
    # Task 3: Ejecutar Dataform (Bronze → Silver → Gold)
    compilar_dataform = DataformCreateCompilationResultOperator(
        task_id="compilar_dataform",
        project_id="pa-prod",
        region="europe-west1",
        repository_id="people-analytics",
        compilation_result={"git_commitish": "main"},
    )
    
    ejecutar_dataform = DataformCreateWorkflowInvocationOperator(
        task_id="ejecutar_dataform",
        project_id="pa-prod",
        region="europe-west1",
        repository_id="people-analytics",
        workflow_invocation={
            "compilation_result": "{{ task_instance.xcom_pull(task_ids='compilar_dataform')['name'] }}"
        },
    )
    
    # Task 4: Verificar calidad de datos
    check_calidad = BigQueryCheckOperator(
        task_id="check_calidad_datos",
        sql="""
        SELECT 
            COUNT(*) > 0 AS tiene_datos,
            COUNT(DISTINCT empleado_id) > 100 AS suficientes_empleados,
            AVG(salario_bruto) BETWEEN 20000 AND 100000 AS salario_razonable
        FROM `pa-prod.people_analytics.gold_metricas_rotacion`
        WHERE fecha_snapshot = '{{ ds }}'
        """,
        use_legacy_sql=False,
    )
    
    # Task 5: Notificar a RRHH
    notificar = PythonOperator(
        task_id="notificar_rrhh",
        python_callable=enviar_notificacion_slack,
        op_kwargs={
            "mensaje": "ETL People Analytics completado para {{ ds }}",
            "canal": "#people-analytics",
        },
    )
    
    # Definir dependencias (el DAG)
    extraer_hris >> cargar_bronze >> compilar_dataform >> ejecutar_dataform >> check_calidad >> notificar
```

**Arquitectura de Cloud Composer:**

```
┌──────────────────────────────────────────────────────┐
│                  Cloud Composer Environment            │
│                                                       │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │  Airflow     │  │  Airflow     │  │   GCS       │ │
│  │  Web Server  │  │  Scheduler   │  │  (DAGs,     │ │
│  │  (UI)        │  │  (orquesta)  │  │   logs,     │ │
│  └─────────────┘  └──────────────┘  │   plugins)  │ │
│                                     └─────────────┘ │
│  ┌────────────────────────────────────────────────┐  │
│  │          GKE Cluster (Workers)                 │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐         │  │
│  │  │Worker 1 │ │Worker 2 │ │Worker N │         │  │
│  │  └─────────┘ └─────────┘ └─────────┘         │  │
│  └────────────────────────────────────────────────┘  │
│                                                       │
│  ┌──────────────────────┐                             │
│  │  Cloud SQL (metadata)│                             │
│  └──────────────────────┘                             │
└──────────────────────────────────────────────────────┘
```

### Aplicación en People Analytics
- Composer cuando el equipo tiene **múltiples pipelines** con dependencias cruzadas (ETL diario, encuestas trimestrales, modelos mensuales, informes regulatorios).
- Cada pipeline es un DAG independiente pero pueden compartir sensores y dependencias.
- La UI de Airflow permite a los analistas ver el estado de los pipelines sin conocer el código.

---

## Tema 5.4: Comparación entre Workflows y Composer

### Detalle técnico

| Dimensión | Cloud Workflows | Cloud Composer (Airflow) |
|-----------|----------------|--------------------------|
| **Modelo** | Serverless, YAML | Managed cluster, Python |
| **Coste mínimo** | ~$0/mes (pay per use) | ~$300-500/mes (cluster GKE) |
| **Escala** | Automática | Manual (ajustar workers) |
| **Complejidad** | Baja-media | Alta |
| **Lenguaje** | YAML/JSON | Python |
| **UI de monitoreo** | Básica (consola GCP) | Completa (Airflow UI) |
| **Máx. pasos por ejecución** | 32.000 | Sin límite práctico |
| **Duración máxima** | 1 año | Sin límite |
| **Scheduling nativo** | No (requiere Cloud Scheduler) | Sí (`schedule_interval`) |
| **Sensores/espera** | No | Sí (sensors, triggers) |
| **Conectores** | HTTP nativo | +200 operators preconstruidos |
| **Backfill** | Manual | Nativo (`catchup=True`) |
| **Variables/secretos** | No nativo | Airflow Variables + Connections |
| **Ideal para** | 3-15 pasos, sin estado, serverless | >15 tareas, dependencias complejas, equipo grande |

**Árbol de decisión:**

```
¿Cuántos pipelines y tareas tienes?
├── < 5 pipelines, < 10 tareas cada uno
│   └── Cloud Workflows + Cloud Scheduler
│       Coste: ~$5/mes | Setup: 1 día
│
├── 5-15 pipelines, tareas complejas
│   └── Cloud Workflows + Dataform (para SQL)
│       Coste: ~$10/mes | Setup: 2-3 días
│
└── > 15 pipelines, dependencias cruzadas, equipo > 5 personas
    └── Cloud Composer
        Coste: ~$400/mes | Setup: 1-2 semanas
```

---

## Tema 5.5: Integración con Eventarc y Cloud Scheduler

### Detalle técnico

**Cloud Scheduler → Workflows (programado):**

```bash
# Crear job de Cloud Scheduler que ejecuta el workflow diariamente
gcloud scheduler jobs create http etl-diario-pa \
    --location=europe-west1 \
    --schedule="0 7 * * 1-5" \  # Lunes a viernes a las 07:00
    --uri="https://workflowexecutions.googleapis.com/v1/projects/pa-prod/locations/europe-west1/workflows/etl-diario-pa/executions" \
    --message-body='{"argument": "{\"fecha\": \"today\"}"}' \
    --oauth-service-account-email=sa-scheduler@pa-prod.iam.gserviceaccount.com \
    --time-zone="Europe/Madrid"
```

**Eventarc → Workflows (reactivo):**

```bash
# Trigger: cuando un archivo llega a GCS → ejecutar workflow
gcloud eventarc triggers create trigger-nomina-workflow \
    --location=europe-west1 \
    --destination-workflow=procesar-nomina \
    --destination-workflow-location=europe-west1 \
    --event-filters="type=google.cloud.storage.object.v1.finalized" \
    --event-filters="bucket=pa-datalake" \
    --event-filters-path-pattern="prefix=/nomina/raw/" \
    --service-account=sa-eventarc@pa-prod.iam.gserviceaccount.com
```

**Patrón híbrido recomendado para People Analytics:**

```
Programado (Cloud Scheduler):
├── 07:00 L-V → Workflow: ETL diario HRIS
├── 01:00 día 1 de mes → Workflow: Proceso mensual nómina
└── 09:00 último viernes de mes → Workflow: Informe mensual rotación

Reactivo (Eventarc):
├── Archivo CSV en /nomina/raw/ → Workflow: Procesar nómina
├── Archivo JSON en /encuestas/raw/ → Cloud Function: Procesar encuesta
└── Archivo en /evaluaciones/raw/ → Workflow: Procesar evaluaciones

Transformación (Dataform):
└── Programado después del ETL → Bronze → Silver → Gold
```

### Aplicación en People Analytics
- **Scheduler** para todo lo predecible: ETL diario, informes mensuales, modelos trimestrales.
- **Eventarc** para lo impredecible: archivos que llegan cuando el equipo de nómina termina, respuestas de encuestas durante una campaña.
- **Combinar ambos**: el Scheduler garantiza que el ETL se ejecuta aunque no haya archivos nuevos (para detectar ausencia de datos). Eventarc garantiza procesamiento inmediato cuando llegan datos fuera del horario habitual.

---

## Recursos adicionales
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Cloud Workflows syntax reference](https://cloud.google.com/workflows/docs/reference/syntax)
- [Cloud Composer Documentation](https://cloud.google.com/composer/docs)
- [Apache Airflow operators for GCP](https://airflow.apache.org/docs/apache-airflow-providers-google/stable/index.html)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [Eventarc → Workflows integration](https://cloud.google.com/eventarc/docs/targets#workflows)
