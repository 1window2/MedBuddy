# 파일명: medication_care_router.py
# 역할: 약 관리·복용 기록 HTTP 요청을 인증된 Control에 전달한다.

from datetime import date

from fastapi import APIRouter, BackgroundTasks, Depends
from sqlalchemy.orm import Session

from api.dependencies import get_authenticated_principal
from api.route_support import queue_completion_alerts
from controls.manage_medication_care_control import ManageMedicationCare
from core.database import get_db
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from schemas.medication_care import DoseHistoryUpdate, RegimenChangeRequest

router = APIRouter(prefix="/care", tags=["Medication care"])


# 함수이름: change_medication
# 함수역할: 약 수정·중단·교체를 요청한다. 상위 라우터의 계정 잠금·App Check를 유지한다.
# 매개변수: medication_id: 기존 약, request: 본문, principal: 주체, db: 공유 세션.
# 반환값: 새 약 또는 중단한 약의 버전 응답.
@router.post("/medications/{medication_id}/change")
def change_medication(
    medication_id: int, request: RegimenChangeRequest,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    db: Session = Depends(get_db),
) -> dict[str, object]:
    return ManageMedicationCare(db).change_medication(principal, medication_id, request)


# 함수이름: get_history
# 함수역할: 환자 또는 활성 보호자에게 제한된 날짜별 사용자 보고를 제공한다.
# 매개변수: start_date/end_date: 범위, patient_hash: 대상, principal: 주체, db: 세션.
# 반환값: 기록과 저장 약 목록.
@router.get("/history")
def get_history(
    start_date: date, end_date: date, patient_hash: str | None = None,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    db: Session = Depends(get_db),
) -> dict[str, object]:
    return ManageMedicationCare(db).history(principal, start_date, end_date, patient_hash)


# 함수이름: update_history
# 함수역할: 환자 본인이 날짜별 상태를 수정하며 필요시 복용의 UUID 시간대를 허용한다.
# 매개변수: medication_id/schedule_date/slot_key: 대상, request: 본문, principal: 주체, db: 세션.
# 반환값: 갱신한 사용자 보고 기록.
@router.put("/history/{medication_id}/{schedule_date}/{slot_key}")
def update_history(
    medication_id: int, schedule_date: date, slot_key: str, request: DoseHistoryUpdate,
    background_tasks: BackgroundTasks,
    principal: AuthenticatedPrincipal = Depends(get_authenticated_principal),
    db: Session = Depends(get_db),
) -> dict[str, object]:
    control = ManageMedicationCare(db)
    response = control.update_history(principal, medication_id, schedule_date, slot_key, request)
    queue_completion_alerts(background_tasks, control.consumeCompletionEvents(), db)
    return response
