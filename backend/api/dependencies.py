# 파일명: dependencies.py
# 역할: 백엔드 유스케이스 협력 객체를 생성하는 FastAPI 의존성 factory를 제공한다.

from fastapi import Depends
from sqlalchemy.orm import Session

from core.database import get_db
from controls.check_medication_detail_control import CheckMedicationDetail
from controls.check_schedule_control import CheckSchedule
from controls.check_saved_medication_control import CheckSavedMedication
from controls.input_prescription_control import InputPrescription
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.request_health_recommendation_control import RequestHealthRecommendation


# 함수명: get_input_prescription
# 함수역할:
# - 처방전 이미지 분석 control 서비스를 생성한다.
# 반환값:
# - InputPrescription instance.
def get_input_prescription() -> InputPrescription:
    return InputPrescription()


# 함수명: get_check_medication_detail
# 함수역할:
# - 선택적 로컬 DB 접근을 포함한 약 상세 조회 control 서비스를 생성한다.
# 매개변수:
# - db: FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - CheckMedicationDetail instance.
def get_check_medication_detail(
    db: Session = Depends(get_db),
) -> CheckMedicationDetail:
    return CheckMedicationDetail(db=db)


# 함수명: get_check_saved_medication
# 함수역할:
# - 요청 단위 DB 세션을 포함한 저장 복약 control 서비스를 생성한다.
# 매개변수:
# - db: FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - CheckSavedMedication instance.
def get_check_saved_medication(
    db: Session = Depends(get_db),
) -> CheckSavedMedication:
    return CheckSavedMedication(db=db)


# 함수명: get_check_schedule
# 함수역할:
# - 요청 단위 DB 세션을 포함한 복약 일정 control 서비스를 생성한다.
# 매개변수:
# - db: FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - CheckSchedule instance.
def get_check_schedule(
    db: Session = Depends(get_db),
) -> CheckSchedule:
    return CheckSchedule(db=db)


# 함수명: get_request_health_recommendation
# 함수역할:
# - 요청 단위 DB 세션을 포함한 건강 관리 추천 control 서비스를 생성한다.
# 매개변수:
# - db: FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - RequestHealthRecommendation instance.
def get_request_health_recommendation(
    db: Session = Depends(get_db),
) -> RequestHealthRecommendation:
    return RequestHealthRecommendation(db=db)


# 함수명: get_link_patient_caregiver
# 함수역할:
# - 요청 단위 DB 세션을 포함한 환자-보호자 연동 control 서비스를 생성한다.
# 매개변수:
# - db: FastAPI 의존성 주입으로 전달된 SQLAlchemy 세션
# 반환값:
# - LinkPatientCaregiver instance.
def get_link_patient_caregiver(
    db: Session = Depends(get_db),
) -> LinkPatientCaregiver:
    return LinkPatientCaregiver(db=db)
