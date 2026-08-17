# 파일명 : image_processing.py
# 역할 : 처방전 이미지를 OCR에 적합한 형태로 전처리하는 유틸리티 함수들을 정의한다.

from io import BytesIO
import warnings

import cv2
import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError

MAX_PRESCRIPTION_IMAGE_PIXELS = 24_000_000


# Function Name: _validate_prescription_image_dimensions
# Description:
# - Rejects malformed or oversized image dimensions from the encoded header.
# - Runs before Pillow or OpenCV allocate decoded prescription pixel buffers.
# Parameters:
# - source: Pillow image opened from the uploaded encoded bytes.
# Returns:
# - None when the encoded image dimensions are safe to decode.
def _validate_prescription_image_dimensions(source: Image.Image) -> None:
    width, height = source.size
    if width <= 0 or height <= 0:
        raise ValueError("Prescription image dimensions are invalid.")
    if width * height > MAX_PRESCRIPTION_IMAGE_PIXELS:
        raise ValueError("Prescription image exceeds the 24 megapixel limit.")

# 함수이름: preprocess_prescription_image
# 함수역할:
# - EXIF 촬영 방향을 실제 픽셀에 반영한다.
# - 명암 변환, 노이즈 제거, 이진화를 적용해 OCR용 JPEG로 변환한다.
# 매개변수:
# - image_bytes: 원본 처방전 이미지 바이트
# 반환값:
# - 방향 보정과 이진화를 마친 JPEG 이미지 바이트
def preprocess_prescription_image(image_bytes: bytes) -> bytes:
    # 1단계: EXIF 회전을 실제 픽셀에 반영하고 OpenCV 이미지 배열로 변환한다.
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(image_bytes)) as source:
                _validate_prescription_image_dimensions(source)
                oriented = ImageOps.exif_transpose(source).convert("RGB")
                img = cv2.cvtColor(np.asarray(oriented), cv2.COLOR_RGB2BGR)
    except (
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
        OSError,
        UnidentifiedImageError,
    ) as exc:
        raise ValueError(
            "이미지를 읽을 수 없습니다. 올바른 파일인지 확인해주세요."
        ) from exc

    # 2단계: 색상 정보를 제거해 회색조 이미지로 변환한다.
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # 3단계: 가우시안 블러로 촬영 노이즈를 줄인다.
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)

    # 4단계: 적응형 이진화로 글자와 배경을 분리한다.
    binary = cv2.adaptiveThreshold(
        blurred,
        255,  # 이진화 결과의 흰색 최댓값
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,  # 주변 픽셀의 가중 평균을 기준으로 사용
        cv2.THRESH_BINARY,  # 기준값보다 큰 픽셀을 흰색으로 변환
        15,  # 주변 밝기를 계산할 홀수 크기의 영역
        5,  # 배경을 줄이기 위한 기준값 보정치
    )

    # 5단계: 전처리 결과를 전송 가능한 JPEG 바이트로 인코딩한다.
    success, encoded_img = cv2.imencode(".jpg", binary)
    if not success:
        raise ValueError("이미지 인코딩 실패")

    return encoded_img.tobytes()
