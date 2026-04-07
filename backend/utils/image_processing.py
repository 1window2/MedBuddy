import cv2
import numpy as np

def preprocess_prescription_image(image_bytes: bytes) -> bytes:
    # 노이즈 제거 및 선명하게 처리
    # 1. 비정형 데이터 처리(OpenCV가 읽는 배열로 변환)
    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    if img is None:
        raise ValueError("이미지를 읽을 수 없습니다. 올바른 파일인지 확인해주세요.")

    # 2. grayscale 변환
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # 3. GaussianBlur: 종이 질감, 노이즈 등 뭉개기
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)

    # 4. Adaptive Thresholding - 글자와 배경 분리
    binary = cv2.adaptiveThreshold(
        blurred, 
        255,                                  # 배경을 완전한 흰색으로
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,       # 주변 픽셀 가중치 계산 방식
        cv2.THRESH_BINARY,                    # 이진화 적용
        15,                                   # Block Size (영역 크기, 홀수)
        5                                     # C값 (배경 날리는 parameter)
    )

    # 5. 전처리 끝낸 이미지를 다시 bytes로 encoding
    success, encoded_img = cv2.imencode('.jpg', binary)
    if not success:
        raise ValueError("이미지 인코딩 실패")
        
    return encoded_img.tobytes()