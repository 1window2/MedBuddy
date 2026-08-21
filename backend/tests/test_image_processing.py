# 파일명: test_image_processing.py
# 역할: 처방전 OCR 전처리에서 촬영 방향과 이미지 크기가 유지되는지 검증한다.

from io import BytesIO
import sys
import struct
import zlib
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from utils.image_processing import (
    MAX_PRESCRIPTION_IMAGE_PIXELS,
    preprocess_prescription_image,
)


def _png_with_dimensions(width: int, height: int) -> bytes:
    def chunk(chunk_type: bytes, payload: bytes) -> bytes:
        checksum = zlib.crc32(chunk_type + payload) & 0xFFFFFFFF
        return (
            struct.pack(">I", len(payload))
            + chunk_type
            + payload
            + struct.pack(">I", checksum)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IEND", b"")


def test_prescription_preprocessing_applies_exif_orientation() -> None:
    # 가로 12, 세로 8 이미지에 시계 방향 90도 회전 정보를 기록한다.
    source = Image.new("RGB", (12, 8), color="white")
    exif = Image.Exif()
    exif[274] = 6
    buffer = BytesIO()
    source.save(buffer, format="JPEG", exif=exif)

    processed_bytes = preprocess_prescription_image(buffer.getvalue())
    processed = cv2.imdecode(
        np.frombuffer(processed_bytes, dtype=np.uint8),
        cv2.IMREAD_GRAYSCALE,
    )

    assert processed is not None
    assert processed.shape == (12, 8)


def test_prescription_preprocessing_rejects_oversized_decoded_dimensions() -> None:
    width = 6_000
    height = (MAX_PRESCRIPTION_IMAGE_PIXELS // width) + 1

    with pytest.raises(ValueError, match="pixel limit"):
        preprocess_prescription_image(_png_with_dimensions(width, height))
