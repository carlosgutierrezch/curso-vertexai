"""Cloud Function: validator.

Recibe {bucket, file} y comprueba si el objeto en GCS es un CV procesable:
existe, tamaño entre 1 KB y 10 MB, extensión .pdf o .docx.

Respuesta: {"valid": bool, "reason": str}
"""

import logging
import os
from typing import Optional

import functions_framework
from google.cloud import storage


class Validator:
    """Comprueba que un objeto de GCS es un CV procesable."""

    DEFAULT_ALLOWED_EXTENSIONS = ".pdf,.docx"

    def __init__(self):
        self.min_size_bytes = int(os.getenv("MIN_SIZE_BYTES", "1024"))
        self.max_size_bytes = int(os.getenv("MAX_SIZE_BYTES", str(10 * 1024 * 1024)))
        self.allowed_extensions = {
            ext.strip().lower()
            for ext in os.getenv("ALLOWED_EXTENSIONS", self.DEFAULT_ALLOWED_EXTENSIONS).split(",")
        }
        self.storage_client = storage.Client()
        self.logger = logging.getLogger(self.__class__.__name__)

    def validate(self, bucket_name: str, file_name: str) -> dict:
        blob = self.storage_client.bucket(bucket_name).get_blob(file_name)
        if blob is None:
            return {"valid": False, "reason": f"object gs://{bucket_name}/{file_name} not found"}

        extension = os.path.splitext(file_name)[1].lower()
        if extension not in self.allowed_extensions:
            return {
                "valid": False,
                "reason": f"extension {extension!r} not in {sorted(self.allowed_extensions)}",
            }

        size = blob.size or 0
        if size < self.min_size_bytes:
            return {"valid": False, "reason": f"file too small: {size} bytes"}
        if size > self.max_size_bytes:
            return {"valid": False, "reason": f"file too large: {size} bytes"}

        self.logger.info("validated gs://%s/%s (%d bytes)", bucket_name, file_name, size)
        return {"valid": True, "reason": "ok", "size": size}


_validator: Optional[Validator] = None


def _get_validator() -> Validator:
    global _validator
    if _validator is None:
        _validator = Validator()
    return _validator


@functions_framework.http
def validate(request):
    payload = request.get_json(silent=True) or {}
    bucket_name = payload.get("bucket")
    file_name = payload.get("file")
    if not bucket_name or not file_name:
        return {"valid": False, "reason": "missing bucket or file in payload"}, 400
    return _get_validator().validate(bucket_name, file_name)
