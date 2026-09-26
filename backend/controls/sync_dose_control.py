# 파일명: sync_dose_control.py
# 역할: 오프라인 복용 요청과 복약 변경, 선택적 채팅 기록을 함께 저장한다.

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from controls.check_schedule_control import CheckSchedule
from controls.manage_linked_chat_control import ChatSendResult, ManageLinkedChat
from entities.dose_sync_operation_entity import _DoseSyncOperation
from schemas.dose_sync import DoseSyncRequest


# 클래스명: SyncDose
# 역할: 환자별 요청 ID로 재전송을 구분하고 복약 변경의 원자성을 유지한다.
# 속성: db - 복약 기록과 처리 영수증을 함께 저장하는 SQLAlchemy 세션.
class SyncDose:
    # 함수이름: __init__
    # 함수역할: 요청에 사용할 DB 세션을 보관한다.
    # 매개변수: db - 인증된 요청의 세션. 반환값: 없음.
    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수이름: apply
    # 함수역할: 처음 받은 요청만 적용하고, 재전송은 원본과 일치하는지 확인한다.
    # 매개변수: patient_hash - 인증된 환자, request - 원래 날짜와 복용 상태.
    # 반환값: 커밋 이후 전달할 완료 이벤트와 선택적 채팅 결과.
    def apply(
        self, patient_hash: str, request: DoseSyncRequest,
    ) -> tuple[list[dict[str, str | int]], ChatSendResult | None]:
        payload = request.model_dump(mode="json")
        key = (patient_hash, request.operation_id)
        existing = self.db.get(_DoseSyncOperation, key)
        if existing is not None:
            self._verify(existing, payload)
            return [], None
        try:
            # 영수증을 먼저 선점하여 동시에 재전송돼도 한 요청만 반영한다.
            self.db.add(_DoseSyncOperation(patient_hash=patient_hash, operation_id=request.operation_id, payload=payload))
            self.db.flush()
            chat_result = None
            if request.link_id is not None:
                chat_result, events = ManageLinkedChat(self.db).record_medication_taken(
                    link_id=request.link_id, sender_hash=patient_hash,
                    client_message_id=request.operation_id,
                    schedule_date=request.schedule_date, slot_key=request.slot_key,
                    medication_ids=request.medication_ids, commit=False, allow_historical=True,
                )
            else:
                schedule = CheckSchedule(self.db)
                schedule.updateMedicationSlotStatus(
                    request.slot_key, request.completed, patient_hash,
                    expected_schedule_date=request.schedule_date,
                    selected_medication_ids=request.medication_ids,
                    commit=False, allow_historical=True,
                )
                events = schedule.consumeCompletionEvents()
            self.db.commit()
            return events, chat_result
        except IntegrityError:
            self.db.rollback()
            existing = self.db.get(_DoseSyncOperation, key)
            if existing is None:
                raise HTTPException(status_code=409, detail="Dose no longer exists.")
            self._verify(existing, payload)
            return [], None
        except Exception:
            self.db.rollback()
            raise

    @staticmethod
    # 함수이름: _verify
    # 함수역할: 같은 요청 ID에 다른 복용 내용을 덮어쓰지 못하게 한다.
    # 매개변수: existing - 저장된 영수증, payload - 재전송 본문.
    # 반환값: 없음. 내용이 다르면 409 오류.
    def _verify(existing: _DoseSyncOperation, payload: dict[str, object]) -> None:
        if existing.payload != payload:
            raise HTTPException(status_code=409, detail="Operation ID was reused with different data.")
