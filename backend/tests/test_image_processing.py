# 파일명: test_image_processing.py
# 역할: 처방전 OCR 전처리에서 촬영 방향과 이미지 크기가 유지되는지 검증한다.

from io import BytesIO
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from utils.image_processing import preprocess_prescription_image


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
