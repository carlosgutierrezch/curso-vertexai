"""Cloud Composer (Airflow) DAG — Pipeline mensual de Retention Risk.

Equivalente al Cloud Workflow `workflows/retention_pipeline.yaml`.
Este DAG se muestra como código pedagógico para comparativa Workflows vs Composer.
NO se despliega en clase (cluster Composer = ~$300/mes y cold start ~25 min).

Para desplegar en producción:
    gcloud composer environments storage dags import \
        --environment=people-analytics-prod \
        --location=europe-southwest1 \
        --source=composer/retention_pipeline_dag.py
"""
from __future__ import annotations

import base64
from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from airflow.providers.google.cloud.operators.pubsub import PubSubPublishMessageOperator
from airflow.utils.trigger_rule import TriggerRule

# ──────────────────────────────────────────────────────────────────────
# Configuración
# ──────────────────────────────────────────────────────────────────────
PROJECT_ID = "people-analytics-formacion"
LOCATION = "europe-southwest1"
TOPIC_STATUS = "retention-pipeline-status"
TOPIC_ALERTS = "retention-pipeline-alerts"

LABELS = {
    "team": "people-analytics",
    "pipeline": "retention-risk",
    "env": "prod",
}

# Macro Jinja para el primer día del mes en curso
TARGET_MONTH = "{{ macros.ds_format(macros.ds_add(ds, -macros.datetime.strptime(ds, '%Y-%m-%d').day + 1), '%Y-%m-%d', '%Y-%m-%d') }}"

default_args = {
    "owner": "people-analytics",
    "depends_on_past": False,
    "email_on_failure": True,
    "email_on_retry": False,
    "email": ["data-eng-team@imagina.es"],
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "max_retry_delay": timedelta(minutes=30),
}


# ──────────────────────────────────────────────────────────────────────
# DAG definition
# ──────────────────────────────────────────────────────────────────────
with DAG(
    dag_id="retention_pipeline",
    default_args=default_args,
    description="Pipeline mensual de retention risk — orquesta SPs de feature_store_retention y predictions_retention.",
    schedule_interval="0 6 1 * *",  # día 1 de cada mes a las 06:00
    start_date=datetime(2025, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=["people-analytics", "retention", "monthly"],
) as dag:

    # ──────────────────────────────────────────────────────────────────
    # Paso 1: Construcción de features
    # ──────────────────────────────────────────────────────────────────
    build_features = BigQueryInsertJobOperator(
        task_id="build_features",
        project_id=PROJECT_ID,
        location=LOCATION,
        configuration={
            "query": {
                "query": (
                    f"CALL `{PROJECT_ID}.feature_store_retention.sp_build_retention_features`"
                    f"(DATE '{TARGET_MONTH}')"
                ),
                "useLegacySql": False,
            },
            "labels": {**LABELS, "step": "build_features"},
            "jobTimeoutMs": "600000",
            "dryRun": False,
        },
    )

    # ──────────────────────────────────────────────────────────────────
    # Paso 2: Aplicar regla de decisión newsvendor
    # ──────────────────────────────────────────────────────────────────
    apply_decision = BigQueryInsertJobOperator(
        task_id="apply_decision",
        project_id=PROJECT_ID,
        location=LOCATION,
        configuration={
            "query": {
                "query": (
                    f"CALL `{PROJECT_ID}.predictions_retention.sp_apply_decision_rule`"
                    f"(DATE '{TARGET_MONTH}')"
                ),
                "useLegacySql": False,
            },
            "labels": {**LABELS, "step": "apply_decision"},
        },
    )

    # ──────────────────────────────────────────────────────────────────
    # Paso 3: Snapshot inmutable de auditoría
    # ──────────────────────────────────────────────────────────────────
    snapshot_audit = BigQueryInsertJobOperator(
        task_id="snapshot_audit",
        project_id=PROJECT_ID,
        location=LOCATION,
        configuration={
            "query": {
                "query": (
                    f"CREATE SNAPSHOT TABLE `{PROJECT_ID}.predictions_retention."
                    f"retention_actions_snap_{{{{ macros.ds_format(macros.ds_add(ds, -macros.datetime.strptime(ds, '%Y-%m-%d').day + 1), '%Y-%m-%d', '%Y%m%d') }}}}_{{{{ ds_nodash }}}}` "
                    f"CLONE `{PROJECT_ID}.predictions_retention.retention_actions` "
                    f"OPTIONS(expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 365 DAY))"
                ),
                "useLegacySql": False,
            },
            "labels": {**LABELS, "step": "snapshot"},
        },
        trigger_rule=TriggerRule.ALL_SUCCESS,
    )

    # ──────────────────────────────────────────────────────────────────
    # Paso 4: Notificación de éxito (Pub/Sub)
    # ──────────────────────────────────────────────────────────────────
    notify_success = PubSubPublishMessageOperator(
        task_id="notify_success",
        project_id=PROJECT_ID,
        topic=TOPIC_STATUS,
        messages=[
            {
                "data": base64.b64encode(
                    f"OK retention-pipeline para {TARGET_MONTH}".encode("utf-8")
                ).decode("utf-8"),
                "attributes": {
                    "pipeline": "retention-risk",
                    "target_month": TARGET_MONTH,
                    "status": "SUCCESS",
                },
            },
        ],
        trigger_rule=TriggerRule.ALL_SUCCESS,
    )

    # ──────────────────────────────────────────────────────────────────
    # Notificación de fallo (se ejecuta solo si algún upstream falla)
    # ──────────────────────────────────────────────────────────────────
    notify_failure = PubSubPublishMessageOperator(
        task_id="notify_failure",
        project_id=PROJECT_ID,
        topic=TOPIC_ALERTS,
        messages=[
            {
                "data": base64.b64encode(
                    f"ERROR retention-pipeline para {TARGET_MONTH}".encode("utf-8")
                ).decode("utf-8"),
                "attributes": {
                    "pipeline": "retention-risk",
                    "target_month": TARGET_MONTH,
                    "status": "FAILED",
                },
            },
        ],
        trigger_rule=TriggerRule.ONE_FAILED,
    )

    # ──────────────────────────────────────────────────────────────────
    # Topología
    # ──────────────────────────────────────────────────────────────────
    build_features >> apply_decision >> snapshot_audit >> notify_success
    [build_features, apply_decision, snapshot_audit] >> notify_failure
