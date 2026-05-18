"""Cloud Function: extractor.

Lee un .md de CV desde GCS, llama a Vertex AI Gemini con structured output
(response_schema) para extraer datos del CV, y sube el JSON resultante a
JSON_BUCKET.

Auth: usa ADC (la Service Account de la Cloud Function). No hay API keys.

Respuesta: {"bucket": <json_bucket>, "file": <json_file>}
"""

import json
import logging
import os
from typing import List, Optional

import functions_framework
from google import genai
from google.cloud import storage
from google.genai import types
from pydantic import BaseModel


class ExtractedCV(BaseModel):
    nombre: Optional[str] = None
    email: Optional[str] = None
    telefono: Optional[str] = None
    anios_experiencia: Optional[float] = None
    skills: List[str] = []
    ultima_empresa: Optional[str] = None


SYSTEM_PROMPT = (
    "Eres un extractor de datos de CVs. Recibes el texto en Markdown de un "
    "currículum y devuelves un JSON con estos campos exactos: nombre, email, "
    "telefono, anios_experiencia (número), skills (lista de strings), "
    "ultima_empresa. Si un campo no aparece, devuelve null (o lista vacía "
    "para skills)."
)


class Extractor:
    """Extrae datos estructurados de un CV en Markdown con Vertex AI Gemini."""

    DEFAULT_MODEL = "gemini-2.5-flash"

    def __init__(self):
        self.json_bucket = os.environ["JSON_BUCKET"]
        self.project_id = os.environ["PROJECT_ID"]
        self.region = os.environ["REGION"]
        self.model_name = os.getenv("MODEL_NAME", self.DEFAULT_MODEL)
        self.temperature = float(os.getenv("TEMPERATURE", "0.0"))
        self.storage_client = storage.Client()
        self.genai_client = genai.Client(
            vertexai=True, project=self.project_id, location=self.region
        )
        self.logger = logging.getLogger(self.__class__.__name__)

    def extract(self, bucket_name: str, file_name: str) -> dict:
        blob = self.storage_client.bucket(bucket_name).get_blob(file_name)
        if blob is None:
            raise FileNotFoundError(f"object gs://{bucket_name}/{file_name} not found")

        markdown = blob.download_as_text()
        extracted = self._invoke_model(markdown)

        base = os.path.splitext(os.path.basename(file_name))[0]
        output_name = f"{base}.json"
        output_blob = self.storage_client.bucket(self.json_bucket).blob(output_name)
        output_blob.upload_from_string(
            json.dumps(extracted, ensure_ascii=False, indent=2),
            content_type="application/json",
        )

        self.logger.info(
            "extracted gs://%s/%s → gs://%s/%s",
            bucket_name, file_name, self.json_bucket, output_name,
        )
        return {"bucket": self.json_bucket, "file": output_name}

    def _invoke_model(self, markdown: str) -> dict:
        response = self.genai_client.models.generate_content(
            model=self.model_name,
            contents=markdown,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_PROMPT,
                response_mime_type="application/json",
                response_schema=ExtractedCV,
                temperature=self.temperature,
            ),
        )
        if response.parsed is not None:
            return response.parsed.model_dump()
        return json.loads(response.text)


_extractor: Optional[Extractor] = None


def _get_extractor() -> Extractor:
    global _extractor
    if _extractor is None:
        _extractor = Extractor()
    return _extractor


@functions_framework.http
def extract(request):
    payload = request.get_json(silent=True) or {}
    try:
        return _get_extractor().extract(payload["bucket"], payload["file"])
    except FileNotFoundError as e:
        return {"error": str(e)}, 404
