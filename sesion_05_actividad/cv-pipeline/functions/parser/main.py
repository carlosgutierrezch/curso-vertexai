"""Cloud Function: parser.

Recibe {bucket, file} apuntando a un PDF o DOCX en GCS, extrae texto y
sube un Markdown equivalente al bucket MARKDOWN_BUCKET.

Respuesta: {"bucket": <markdown_bucket>, "file": <markdown_file>}
"""

import io
import logging
import os
from typing import Optional

import functions_framework
from docx import Document
from google.cloud import storage
from pypdf import PdfReader


class Parser:
    """Convierte PDF/DOCX a Markdown y lo persiste en GCS."""

    def __init__(self):
        self.markdown_bucket = os.environ["MARKDOWN_BUCKET"]
        self.storage_client = storage.Client()
        self.logger = logging.getLogger(self.__class__.__name__)

    def parse(self, bucket_name: str, file_name: str) -> dict:
        blob = self.storage_client.bucket(bucket_name).get_blob(file_name)
        if blob is None:
            raise FileNotFoundError(f"object gs://{bucket_name}/{file_name} not found")

        data = blob.download_as_bytes()
        extension = os.path.splitext(file_name)[1].lower()

        if extension == ".pdf":
            markdown = self._pdf_to_markdown(data)
        elif extension == ".docx":
            markdown = self._docx_to_markdown(data)
        else:
            raise ValueError(f"unsupported extension {extension!r}")

        base = os.path.splitext(os.path.basename(file_name))[0]
        output_name = f"{base}.md"
        output_blob = self.storage_client.bucket(self.markdown_bucket).blob(output_name)
        output_blob.upload_from_string(markdown, content_type="text/markdown")

        self.logger.info(
            "parsed gs://%s/%s → gs://%s/%s (%d chars)",
            bucket_name, file_name, self.markdown_bucket, output_name, len(markdown),
        )
        return {"bucket": self.markdown_bucket, "file": output_name, "chars": len(markdown)}

    def _pdf_to_markdown(self, data: bytes) -> str:
        reader = PdfReader(io.BytesIO(data))
        pages = []
        for i, page in enumerate(reader.pages, start=1):
            text = (page.extract_text() or "").strip()
            pages.append(f"## Página {i}\n\n{text}")
        return "\n\n".join(pages)

    def _docx_to_markdown(self, data: bytes) -> str:
        doc = Document(io.BytesIO(data))
        paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
        return "\n\n".join(paragraphs)


_parser: Optional[Parser] = None


def _get_parser() -> Parser:
    global _parser
    if _parser is None:
        _parser = Parser()
    return _parser


@functions_framework.http
def parse(request):
    payload = request.get_json(silent=True) or {}
    try:
        return _get_parser().parse(payload["bucket"], payload["file"])
    except FileNotFoundError as e:
        return {"error": str(e)}, 404
    except ValueError as e:
        return {"error": str(e)}, 400
