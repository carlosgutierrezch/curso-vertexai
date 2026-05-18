"""Cloud Function: loader.

Lee un JSON estructurado desde GCS, le añade `source_file` y `processed_at`,
y lo inserta en BigQuery como una fila en BQ_DATASET.BQ_TABLE.

Auto-curativo: en cold start ejecuta DDL idempotente (CREATE SCHEMA / TABLE
IF NOT EXISTS) y cachea el resultado en una instancia. Si la tabla se borra
externamente, la siguiente instancia fría la recrea sola.

Respuesta: {"ok": bool, "row": <file_name>}
"""

import json
import logging
import os
from datetime import datetime, timezone
from typing import Optional

import functions_framework
from google.cloud import bigquery, storage


TABLE_SCHEMA_DDL = """
CREATE SCHEMA IF NOT EXISTS `{project}.{dataset}`
  OPTIONS(location="{location}");

CREATE TABLE IF NOT EXISTS `{project}.{dataset}.{table}` (
  nombre            STRING,
  email             STRING,
  telefono          STRING,
  anios_experiencia FLOAT64,
  skills            ARRAY<STRING>,
  ultima_empresa    STRING,
  source_file       STRING,
  processed_at      TIMESTAMP,
  ddate             TIMESTAMP,
);
"""


class Loader:
    """Inserta filas en BigQuery garantizando el dataset y la tabla."""

    def __init__(self):
        self.bq_dataset = os.environ["BQ_DATASET"]
        self.bq_table = os.environ["BQ_TABLE"]
        self.bq_location = os.environ["BQ_LOCATION"]
        self.bq_client = bigquery.Client()
        self.storage_client = storage.Client()
        self._table_ensured = False
        self.logger = logging.getLogger(self.__class__.__name__)

    def load(self, bucket_name: str, file_name: str) -> dict:
        blob = self.storage_client.bucket(bucket_name).get_blob(file_name)
        if blob is None:
            raise FileNotFoundError(f"object gs://{bucket_name}/{file_name} not found")

        row = json.loads(blob.download_as_text())
        row["source_file"] = file_name
        row["processed_at"] = datetime.now(timezone.utc).isoformat()

        table_id = self._ensure_table()
        errors = self.bq_client.insert_rows_json(table_id, [row])
        if errors:
            self.logger.error("BigQuery insert errors: %s", errors)
            return {"ok": False, "errors": errors}

        self.logger.info("loaded gs://%s/%s into %s", bucket_name, file_name, table_id)
        return {"ok": True, "row": file_name}

    def _ensure_table(self) -> str:
        """Crea dataset + tabla si no existen. Idempotente. Cachea por instancia."""
        table_id = f"{self.bq_client.project}.{self.bq_dataset}.{self.bq_table}"
        if self._table_ensured:
            return table_id

        ddl = TABLE_SCHEMA_DDL.format(
            project=self.bq_client.project,
            dataset=self.bq_dataset,
            table=self.bq_table,
            location=self.bq_location,
        )
        self.logger.info("ensuring %s exists in %s", table_id, self.bq_location)
        self.bq_client.query(ddl, location=self.bq_location).result()
        self._table_ensured = True
        return table_id


_loader: Optional[Loader] = None


def _get_loader() -> Loader:
    global _loader
    if _loader is None:
        _loader = Loader()
    return _loader


@functions_framework.http
def load(request):
    payload = request.get_json(silent=True) or {}
    try:
        result = _get_loader().load(payload["bucket"], payload["file"])
        return result if result.get("ok") else (result, 500)
    except FileNotFoundError as e:
        return {"ok": False, "error": str(e)}, 404
