# 파일명: medication_care_receipts.py
# 역할: 삭제된 약의 변경 영수증에서 건강정보를 비우되 재전송 방지 행은 보존한다.
"""약 삭제 시 응답의 건강정보만 지우고 재전송 방지 표식은 보존한다."""

import json

from sqlalchemy import or_
from sqlalchemy.orm import Session

from entities.medication_care_entity import _MedicationCareOperation
from entities.saved_medication_entity import _SavedMedication


# 함수이름: redact_medication_care_receipts
# 함수역할: 대상 약·대체 약의 영수증을 잠가 응답을 지우고 소유 약이 불명확한 구버전 영수증도 보수적으로 정리한다.
# 매개변수: db (Session)는 약을 먼저 잠근 호출자의 트랜잭션, patient_hash (str)는 환자 범위, medication_id (int)는 삭제 약 ID다.
# 반환값: None. flush만 수행하며 commit은 호출자 책임이다. DB 오류는 전달한다.
def redact_medication_care_receipts(db: Session, patient_hash: str, medication_id: int) -> None:
    # 호출자는 먼저 대상 약을 잠근다. 새 기록 저장과 영수증 정리가 교차하지 않게 한다.
    receipts = db.query(_MedicationCareOperation).filter(
        _MedicationCareOperation.patient_hash == patient_hash,
        _MedicationCareOperation.response_redacted.is_(False),
        or_(
            _MedicationCareOperation.medication_id == medication_id,
            _MedicationCareOperation.replacement_medication_id == medication_id,
            _MedicationCareOperation.medication_id.is_(None),
        ),
    ).with_for_update().populate_existing().all()
    for receipt in receipts:
        if receipt.medication_id is None:
            # 구버전 서버가 남긴 영수증도 처리한다. 소유 약을 알 수 없으면 보수적으로 비운다.
            try:
                payload = json.loads(receipt.response_json)
                legacy_id = payload.get("medication_id", payload.get("id")) if isinstance(payload, dict) else None
            except (TypeError, ValueError):
                legacy_id = None
            if type(legacy_id) is int and legacy_id > 0 and legacy_id != medication_id:
                original = db.get(_SavedMedication, medication_id)
                if (
                    not isinstance(payload, dict) or "medication_id" in payload
                    or original is None or original.superseded_by_id != legacy_id
                ):
                    continue
        receipt.response_json = "{}"
        receipt.response_redacted = True
        receipt.medication_id = None
        receipt.replacement_medication_id = None
    # autoflush가 꺼진 세션에서도 다음 약의 구버전 영수증 조회가 비운 값을 덮지 않게 한다.
    db.flush()
