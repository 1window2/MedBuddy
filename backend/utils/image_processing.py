# 파일명 : image_processing.py
# 역할 : 처방전 이미지를 OCR에 적합한 형태로 전처리하는 유틸리티 함수들을 정의한다.

import cv2
import numpy as np

# 함수 이름 : preprocess_prescription_image
# 기능 : 입력된 이미지(bytes)를 OCR 성능 향상을 위해 전처리하여 반환한다.
# 파라미터 :
#   - image_bytes (bytes) : 원본 처방전 이미지 데이터
# 반환값 :
#   - bytes : 전처리된 이미지 데이터 (이진화된 JPG)
# 비고 :
#   - OpenCV 기반으로 grayscale, blur, thresholding을 수행
#   - OCR 인식률 향상을 위한 전처리 단계
def preprocess_prescription_image(image_bytes: bytes) -> bytes:
    # Step 1 : bytes 데이터를 OpenCV 이미지 배열로 변환
    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    if img is None:
        raise ValueError("이미지를 읽을 수 없습니다. 올바른 파일인지 확인해주세요.")

    # Step 2 : 이미지를 grayscale로 변환 (색상 정보 제거)
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # Step 3 : GaussianBlur를 적용하여 노이즈 제거 및 이미지 부드럽게 처리
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)

    # Step 4 : Adaptive Thresholding으로 글자와 배경을 분리 (이진화)
    binary = cv2.adaptiveThreshold(
        blurred, 
        255,                                  # 최대값 (흰색)
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,       # 주변 픽셀 가중치 계산 방식
        cv2.THRESH_BINARY,                    # 이진화 적용
        15,                                   # 블록 크기 (영역 크기, 홀수)
        5                                     # threshhold 보정값 (배경 날리는 parameter)
    )

    # Step 5 : 전처리된 이미지를 다시 bytes 형태로 인코딩
    success, encoded_img = cv2.imencode('.jpg', binary)
    if not success:
        raise ValueError("이미지 인코딩 실패")
        
    return encoded_img.tobytes()  # 최종 전처리 결과 반환
