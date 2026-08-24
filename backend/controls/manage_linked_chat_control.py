# 파일명: manage_linked_chat_control.py
# 역할: 활성 환자·보호자 연동 안에서 채팅 기록을 관리한다.

"""활성 환자·보호자 연동 안에서 채팅 기록을 관리한다."""

from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from core.application_clock import application_today
from entities.chat_message_entity import (
    CHAT_MESSAGE_KIND_MEDICATION_DISCOMFORT,
    CHAT_MESSAGE_KIND_MEDICATION_SHORTAGE,
    CHAT_MESSAGE_KIND_PHARMACY_PHONE_VERIFIED,
    CHAT_MESSAGE_KIND_PHARMACY_SHARE,
    CHAT_MESSAGE_KIND_SLOT_CHECK_REQUEST,
    CHAT_MESSAGE_KIND_SLOT_COMPLETION,
    CHAT_MESSAGE_KIND_TEXT,
    MAX_CHAT_MEDICATION_CONTEXTS,
    ChatMessage,
    _ChatMessage,
)
from entities.medication_alarm_entity import _MedicationAlarm, default_alarm_hour
from entities.medication_completion_entity import _MedicationCompletion
from entities.medication_image_url_entity import safe_medication_image_url
from entities.medication_schedule_entity import (
    MEDICATION_SCHEDULE_SLOT_KEYS,
    decode_medication_schedule_slot_keys,
    medication_schedule_slot_keys_for_frequency,
)
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from entities.saved_medication_entity import _SavedMedication
from repositories.chat_message_repository import ChatMessageRepository
from repositories.patient_caregiver_link_repository import (
    PatientCaregiverLinkRepository,
)
from repositories.pharmacy_catalog_repository import PharmacyCatalogRepository
from repositories.saved_medication_repository import SavedMedicationRepository
from services.medication_course_policy import MedicationCoursePolicy


# 함수이름: utc_now
# 함수역할: 데이터베이스에 기록할 시간대 정보 없는 UTC 현재 시각을 만든다.
# 매개변수: 없음
# 반환값: UTC 기준 datetime
def utc_now() -> datetime:
    """DB에 기록할 시간대 정보 없는 UTC 현재 시각을 반환한다."""
    return datetime.now(UTC).replace(tzinfo=None)


def utc_iso(value: datetime | None) -> str | None:
    """시간대 유무와 관계없이 날짜 시각을 UTC ISO 문자열로 변환한다."""
    if value is None:
        return None
    utc_value = value.replace(tzinfo=UTC) if value.tzinfo is None else value
    return utc_value.astimezone(UTC).isoformat()


# 클래스명: ChatSendResult
# 역할: 저장된 메시지, 수신자와 신규 저장 여부를 함께 전달한다.
# 주요 책임: 중복 전송 결과를 API 계층에서 구분할 수 있게 한다.
@dataclass(frozen=True)
class ChatSendResult:
    """메시지 응답과 신규 저장 여부 및 수신자를 함께 전달한다."""

    message: ChatMessage
    recipient_hash: str
    created: bool


# 클래스명: ManageLinkedChat
# 역할: 활성 환자·보호자 연동 안에서 채팅 사용 사례를 수행한다.
# 주요 책임: 권한 검증, 기록 조회, 복약 맥락 검증, 저장과 읽음 처리를 조율한다.
class ManageLinkedChat:
    """채팅 접근 권한, 저장, 기록 조회, 읽음 처리를 조율한다."""

    def __init__(
        self,
        db: Session,
        *,
        link_repository: PatientCaregiverLinkRepository | None = None,
        message_repository: ChatMessageRepository | None = None,
        medication_repository: SavedMedicationRepository | None = None,
        pharmacy_repository: PharmacyCatalogRepository | None = None,
        course_policy: MedicationCoursePolicy | None = None,
    ) -> None:
        self.db = db
        self.link_repository = link_repository or PatientCaregiverLinkRepository(db)
        self.message_repository = message_repository or ChatMessageRepository(db)
        self.medication_repository = (
            medication_repository or SavedMedicationRepository(db)
        )
        self.pharmacy_repository = pharmacy_repository or PharmacyCatalogRepository(db)
        self.course_policy = course_policy or MedicationCoursePolicy()

    # 함수이름: request_history
    # 함수역할: 참여자에게 연동별 채팅 기록 한 페이지를 반환한다.
    # 매개변수: link_id, user_hash, before_message_id, limit
    # 반환값: 채팅 기록과 다음 페이지 존재 여부
    def request_history(
        self,
        *,
        link_id: int,
        user_hash: str,
        before_message_id: int | None,
        limit: int,
    ) -> dict[str, object]:
        """참여자에게 연동별 채팅 기록 한 페이지를 반환한다."""
        self.require_active_link(link_id=link_id, user_hash=user_hash)
        rows, has_more = self.message_repository.list_recent(
            link_id,
            before_message_id=before_message_id,
            limit=limit,
        )
        return {
            "success": True,
            "data": [ChatMessage.from_row(row).to_response_dict() for row in rows],
            "has_more": has_more,
        }

    # 함수이름: request_medication_contexts
    # 함수역할: 연동 환자가 오늘 복용 중인 약을 채팅 선택 목록으로 반환한다.
    # 매개변수: link_id, user_hash
    # 반환값: 선택 가능한 복약 정보 목록
    def request_medication_contexts(
        self,
        *,
        link_id: int,
        user_hash: str,
    ) -> dict[str, object]:
        """연동 환자가 오늘 복용 중인 약을 두 참여자에게 동일하게 반환한다."""
        link = self.require_active_link(link_id=link_id, user_hash=user_hash)
        today = application_today()
        medications = self._active_medications(str(link.patient_hash), today)
        return {
            "success": True,
            "data": [self._medication_context_response(item) for item in medications],
        }

    # 함수이름: request_schedule_contexts
    # 함수역할: 연동 환자의 오늘 복약을 시간대별 채팅 카드 정보로 묶어 반환한다.
    # 매개변수: link_id, user_hash
    # 반환값: 시간대별 알림 시각, 완료 수와 약 목록
    def request_schedule_contexts(
        self,
        *,
        link_id: int,
        user_hash: str,
    ) -> dict[str, object]:
        """두 참여자가 같은 시간대별 복약 상태를 확인하도록 반환한다."""
        link = self.require_active_link(link_id=link_id, user_hash=user_hash)
        contexts = self._schedule_contexts_for_patient(str(link.patient_hash))
        can_request_check = user_hash == str(link.caregiver_hash)
        for context in contexts:
            context["can_request_check"] = can_request_check
        return {
            "success": True,
            "data": contexts,
        }

    # 함수이름: request_medication_detail
    # 함수역할: 채팅 참여자에게 연동 환자가 저장한 약의 상세정보를 반환한다.
    # 매개변수: link_id, user_hash, medication_id
    # 반환값: 권한이 확인된 저장 복약 상세정보
    def request_medication_detail(
        self,
        *,
        link_id: int,
        user_hash: str,
        medication_id: int,
    ) -> dict[str, object]:
        """채팅 약 카드를 누른 참여자에게 환자 소유 상세정보를 반환한다."""
        link = self.require_active_link(link_id=link_id, user_hash=user_hash)
        medication = self.medication_repository.find_owned_by_id(
            medication_id,
            str(link.patient_hash),
        )
        if medication is None:
            raise HTTPException(
                status_code=404,
                detail="Medication detail was not found for this chat.",
            )
        return {
            "success": True,
            "data": self._medication_detail_response(medication),
        }

    # 함수이름: send_message
    # 함수역할: 일반 또는 복약 맥락 메시지를 멱등하게 저장하고 상대 참여자를 반환한다.
    # 매개변수: link_id, sender_hash, client_message_id, body, medication_id, medication_ids
    # 반환값: ChatSendResult
    def send_message(
        self,
        *,
        link_id: int,
        sender_hash: str,
        client_message_id: str,
        body: str,
        medication_id: int | None = None,
        medication_ids: list[int] | None = None,
        message_kind: str = CHAT_MESSAGE_KIND_TEXT,
        slot_key: str | None = None,
        pharmacy_id: str | None = None,
        allow_internal: bool = False,
    ) -> ChatSendResult:
        """메시지를 한 번만 저장하고 상대 사용자 식별자를 반환한다."""
        link = self.require_active_link(link_id=link_id, user_hash=sender_hash)
        recipient_hash = self._other_participant(link, sender_hash)
        existing = self.message_repository.find_client_request(
            link_id=link_id,
            sender_hash=sender_hash,
            client_message_id=client_message_id,
        )
        if existing is not None:
            return ChatSendResult(
                message=ChatMessage.from_row(existing),
                recipient_hash=recipient_hash,
                created=False,
            )

        selected_medication_ids: list[int] = []
        for selected_id in [medication_id, *(medication_ids or [])]:
            if selected_id is not None and selected_id not in selected_medication_ids:
                selected_medication_ids.append(selected_id)
        if len(selected_medication_ids) > MAX_CHAT_MEDICATION_CONTEXTS:
            raise HTTPException(
                status_code=400,
                detail=(
                    "A chat message can include at most "
                    f"{MAX_CHAT_MEDICATION_CONTEXTS} medications."
                ),
            )
        medications = [
            self._resolve_active_medication(link, selected_id)
            for selected_id in selected_medication_ids
        ]
        medication = medications[0] if medications else None
        context_payload = self._build_message_context(
            link=link,
            sender_hash=sender_hash,
            message_kind=message_kind,
            medication=medication,
            slot_key=slot_key,
            pharmacy_id=pharmacy_id,
            allow_internal=allow_internal,
        )
        if medications:
            context_payload = dict(context_payload or {})
            context_payload["medication_contexts"] = [
                self._medication_context_response(item) for item in medications
            ]
        row = _ChatMessage(
            link_id=link_id,
            sender_hash=sender_hash,
            client_message_id=client_message_id,
            body=body,
            message_kind=message_kind,
            context_payload=context_payload,
            medication_id=(int(medication.id) if medication is not None else None),
            medication_name=(
                str(medication.item_name) if medication is not None else None
            ),
            medication_image_url=(
                safe_medication_image_url(medication.image_url)
                if medication is not None
                else None
            ),
            medication_dosage=(
                (medication.dosage_per_time or "").strip()
                if medication is not None
                else None
            ),
        )
        try:
            self.message_repository.add(row)
            self.db.commit()
            self.db.refresh(row)
        except IntegrityError:
            self.db.rollback()
            existing = self.message_repository.find_client_request(
                link_id=link_id,
                sender_hash=sender_hash,
                client_message_id=client_message_id,
            )
            if existing is None:
                raise
            return ChatSendResult(
                message=ChatMessage.from_row(existing),
                recipient_hash=recipient_hash,
                created=False,
            )
        return ChatSendResult(
            message=ChatMessage.from_row(row),
            recipient_hash=recipient_hash,
            created=True,
        )

    # 함수이름: publish_slot_completion
    # 함수역할: 한 시간대의 약을 모두 복용하면 모든 활성 보호자 채팅에 완료 기록을 남긴다.
    # 매개변수: patient_hash, slot_key
    # 반환값: 새로 저장된 완료 메시지 수
    def publish_slot_completion(self, *, patient_hash: str, slot_key: str) -> int:
        """기존 알림 아웃박스와 같은 완료 사건을 채팅에도 멱등하게 기록한다."""
        if slot_key not in MEDICATION_SCHEDULE_SLOT_KEYS:
            return 0
        slot_labels = {
            "morning": "아침",
            "lunch": "점심",
            "evening": "저녁",
            "bedtime": "취침 전",
        }
        today = application_today()
        created_count = 0
        for link in self.link_repository.list_active_for_patient(patient_hash):
            result = self.send_message(
                link_id=int(link.id),
                sender_hash=patient_hash,
                client_message_id=(
                    f"slot_complete_{today.strftime('%Y%m%d')}_{slot_key}"
                ),
                body=f"{slot_labels[slot_key]} 약 복용을 모두 완료했습니다.",
                message_kind=CHAT_MESSAGE_KIND_SLOT_COMPLETION,
                slot_key=slot_key,
                allow_internal=True,
            )
            if result.created:
                created_count += 1
        return created_count

    # 함수이름: mark_read
    # 함수역할: 상대 메시지를 지정한 범위까지 읽음 처리한다.
    # 매개변수: link_id, reader_hash, through_message_id
    # 반환값: 변경 개수와 마지막 읽음 메시지 정보
    def mark_read(
        self,
        *,
        link_id: int,
        reader_hash: str,
        through_message_id: int | None,
    ) -> dict[str, object]:
        """상대가 보낸 메시지를 읽음 처리하고 변경 범위를 반환한다."""
        self.require_active_link(link_id=link_id, user_hash=reader_hash)
        read_at = utc_now()
        count, last_read_message_id = self.message_repository.mark_incoming_read(
            link_id=link_id,
            reader_hash=reader_hash,
            through_message_id=through_message_id,
            read_at=read_at,
        )
        self.db.commit()
        return {
            "success": True,
            "data": {
                "updated_count": count,
                "through_message_id": last_read_message_id,
                "read_at": read_at.replace(tzinfo=UTC).isoformat(),
            },
        }

    # 함수이름: request_unread_count
    # 함수역할: 현재 사용자가 읽지 않은 상대 메시지 수를 반환한다.
    # 매개변수: link_id, user_hash
    # 반환값: 읽지 않은 메시지 수
    def request_unread_count(
        self,
        *,
        link_id: int,
        user_hash: str,
    ) -> dict[str, object]:
        """현재 연동에서 사용자가 읽지 않은 메시지 수를 반환한다."""
        self.require_active_link(link_id=link_id, user_hash=user_hash)
        return {
            "success": True,
            "data": {
                "unread_count": self.message_repository.unread_count(
                    link_id=link_id,
                    reader_hash=user_hash,
                )
            },
        }

    # 함수이름: require_active_link
    # 함수역할: 사용자가 참여한 활성 연동을 반환하거나 접근을 거부한다.
    # 매개변수: link_id, user_hash
    # 반환값: 활성 환자·보호자 연동
    def require_active_link(
        self,
        *,
        link_id: int,
        user_hash: str,
    ) -> _PatientCaregiverLink:
        """현재 사용자가 참여한 활성 연동을 반환하거나 접근을 거부한다."""
        link = self.link_repository.find_active_for_user_by_id(link_id, user_hash)
        if link is None:
            raise HTTPException(
                status_code=404,
                detail="Active patient-caregiver chat was not found.",
            )
        return link

    def _resolve_active_medication(
        self,
        link: _PatientCaregiverLink,
        medication_id: int,
    ) -> _SavedMedication:
        """선택한 약이 연동 환자의 현재 복용 약인지 검증한다."""
        medication = self.medication_repository.find_owned_by_id(
            medication_id,
            str(link.patient_hash),
        )
        if medication is None or not self.course_policy.is_active_on(
            medication,
            application_today(),
        ):
            raise HTTPException(
                status_code=400,
                detail="Selected medication is not active for this patient.",
            )
        if not (medication.item_name or "").strip():
            raise HTTPException(
                status_code=400,
                detail="Selected medication does not have a display name.",
            )
        return medication

    def _active_medications(
        self,
        patient_hash: str,
        target_date: date,
    ) -> list[_SavedMedication]:
        """환자의 지정일 활성 약을 이름이 있는 항목으로 제한해 반환한다."""
        return [
            medication
            for medication in self.medication_repository.list_by_patient(patient_hash)
            if self.course_policy.is_active_on(medication, target_date)
            and (medication.item_name or "").strip()
        ]

    def _schedule_contexts_for_patient(
        self,
        patient_hash: str,
    ) -> list[dict[str, object]]:
        """활성 약, 완료 기록과 알림 설정을 한 번씩 조회해 시간대별로 묶는다."""
        today = application_today()
        medications = self._active_medications(patient_hash, today)
        medication_ids = [int(item.id) for item in medications if item.id is not None]
        completion_rows = (
            self.db.query(_MedicationCompletion)
            .filter(
                _MedicationCompletion.patient_hash == patient_hash,
                _MedicationCompletion.schedule_date == today,
                _MedicationCompletion.saved_medication_id.in_(medication_ids),
            )
            .all()
            if medication_ids
            else []
        )
        completion_by_key = {
            (int(row.saved_medication_id), str(row.slot_key)): bool(row.completed)
            for row in completion_rows
        }
        alarm_by_slot = {
            str(row.slot_key): row
            for row in (
                self.db.query(_MedicationAlarm)
                .filter(_MedicationAlarm.patient_hash == patient_hash)
                .all()
            )
        }
        grouped: dict[str, list[dict[str, object]]] = {
            slot_key: [] for slot_key in MEDICATION_SCHEDULE_SLOT_KEYS
        }
        completed_count = {slot_key: 0 for slot_key in MEDICATION_SCHEDULE_SLOT_KEYS}
        for medication in medications:
            medication_context = self._medication_context_response(medication)
            legacy_completed = (
                bool(medication.medication_status)
                and medication.medication_status_date == today
            )
            for slot_key in medication_context["schedule_slot_keys"]:
                if slot_key not in grouped:
                    continue
                grouped[slot_key].append(medication_context)
                is_completed = completion_by_key.get(
                    (int(medication.id), slot_key),
                    legacy_completed,
                )
                if is_completed:
                    completed_count[slot_key] += 1

        response: list[dict[str, object]] = []
        for slot_key in MEDICATION_SCHEDULE_SLOT_KEYS:
            slot_medications = grouped[slot_key]
            if not slot_medications:
                continue
            alarm = alarm_by_slot.get(slot_key)
            hour = int(alarm.hour) if alarm is not None else default_alarm_hour(slot_key)
            minute = int(alarm.minute) if alarm is not None else 0
            response.append(
                {
                    "slot_key": slot_key,
                    "alarm_time": f"{hour:02d}:{minute:02d}",
                    "alarm_enabled": bool(alarm.enabled) if alarm is not None else False,
                    "completed_count": completed_count[slot_key],
                    "total_count": len(slot_medications),
                    "medications": slot_medications,
                }
            )
        return response

    def _build_message_context(
        self,
        *,
        link: _PatientCaregiverLink,
        sender_hash: str,
        message_kind: str,
        medication: _SavedMedication | None,
        slot_key: str | None,
        pharmacy_id: str | None,
        allow_internal: bool,
    ) -> dict[str, object] | None:
        """메시지 유형별 입력을 검증하고 서버가 신뢰할 스냅샷만 생성한다."""
        if message_kind == CHAT_MESSAGE_KIND_TEXT:
            return None
        if message_kind in (
            CHAT_MESSAGE_KIND_SLOT_CHECK_REQUEST,
            CHAT_MESSAGE_KIND_SLOT_COMPLETION,
        ):
            if message_kind == CHAT_MESSAGE_KIND_SLOT_CHECK_REQUEST and (
                sender_hash != str(link.caregiver_hash)
            ):
                raise HTTPException(
                    status_code=403,
                    detail="Only the linked caregiver can request a slot check.",
                )
            if message_kind == CHAT_MESSAGE_KIND_SLOT_COMPLETION and not allow_internal:
                raise HTTPException(
                    status_code=403,
                    detail="Slot completion messages are created by the server.",
                )
            slot_context = self._find_slot_context(
                patient_hash=str(link.patient_hash),
                slot_key=slot_key,
            )
            return {"schedule_context": slot_context}
        if message_kind in (
            CHAT_MESSAGE_KIND_MEDICATION_SHORTAGE,
            CHAT_MESSAGE_KIND_MEDICATION_DISCOMFORT,
        ):
            if medication is None:
                raise HTTPException(
                    status_code=400,
                    detail="This message kind requires an active medication.",
                )
            context = self._medication_course_context(medication)
            if message_kind == CHAT_MESSAGE_KIND_MEDICATION_DISCOMFORT:
                context["show_safety_guidance"] = True
            return context
        if message_kind in (
            CHAT_MESSAGE_KIND_PHARMACY_SHARE,
            CHAT_MESSAGE_KIND_PHARMACY_PHONE_VERIFIED,
        ):
            pharmacy = self.pharmacy_repository.find_by_id(pharmacy_id or "")
            if pharmacy is None:
                raise HTTPException(status_code=400, detail="Pharmacy was not found.")
            return {
                "pharmacy_context": {
                    "pharmacy_id": pharmacy.pharmacy_id,
                    "name": pharmacy.name,
                    "address": pharmacy.address,
                    "telephone": pharmacy.telephone,
                    "today_hours": self._pharmacy_today_hours(pharmacy),
                    "latitude": pharmacy.latitude,
                    "longitude": pharmacy.longitude,
                    "source_updated_at": utc_iso(pharmacy.source_updated_at),
                }
            }
        raise HTTPException(status_code=400, detail="Unsupported chat message kind.")

    @staticmethod
    def _pharmacy_today_hours(pharmacy: object) -> str:
        """약국 카탈로그의 오늘 정규 운영시간을 채팅 표시 형식으로 바꾼다."""
        weekly_hours = getattr(pharmacy, "weekly_hours", None)
        if not isinstance(weekly_hours, dict):
            return ""
        raw_hours = weekly_hours.get(str(application_today().isoweekday()))
        if not isinstance(raw_hours, (list, tuple)) or len(raw_hours) < 2:
            return ""
        open_time = ManageLinkedChat._format_pharmacy_time(raw_hours[0])
        close_time = ManageLinkedChat._format_pharmacy_time(raw_hours[1])
        if not open_time or not close_time:
            return ""
        return f"{open_time} - {close_time}"

    @staticmethod
    def _format_pharmacy_time(value: object) -> str:
        """공공데이터의 HHMM 운영시간을 읽기 쉬운 HH:MM으로 정규화한다."""
        digits = "".join(
            character
            for character in str(value or "")
            if character.isdigit()
        )
        if len(digits) not in (3, 4):
            return ""
        digits = digits.zfill(4)
        hour = int(digits[:2])
        minute = int(digits[2:])
        if hour > 24 or minute > 59 or (hour == 24 and minute != 0):
            return ""
        return f"{hour:02d}:{minute:02d}"

    def _find_slot_context(
        self,
        *,
        patient_hash: str,
        slot_key: str | None,
    ) -> dict[str, object]:
        """현재 복약 일정에 실제로 존재하는 시간대 맥락을 반환한다."""
        if slot_key not in MEDICATION_SCHEDULE_SLOT_KEYS:
            raise HTTPException(status_code=400, detail="Invalid schedule slot.")
        for context in self._schedule_contexts_for_patient(patient_hash):
            if context["slot_key"] == slot_key:
                return context
        raise HTTPException(
            status_code=400,
            detail="The selected schedule slot has no active medication.",
        )

    def _medication_course_context(
        self,
        medication: _SavedMedication,
    ) -> dict[str, object]:
        """약 부족 메시지에서 사용할 남은 복용 기간을 계산한다."""
        today = application_today()
        start_date = self.course_policy.read_start_date(medication, today)
        total_days = self.course_policy.read_total_days(medication.total_days)
        if total_days <= 0:
            return {"remaining_days": None, "course_end_date": None}
        end_date = start_date + timedelta(days=total_days - 1)
        return {
            "remaining_days": max((end_date - today).days + 1, 0),
            "course_end_date": end_date.isoformat(),
        }

    def _medication_context_response(
        self,
        medication: _SavedMedication,
    ) -> dict[str, object]:
        """복약 목록 행을 오늘 일정형 채팅 선택기에 필요한 정보로 변환한다."""
        schedule_slot_keys = decode_medication_schedule_slot_keys(
            medication.schedule_slot_keys
        )
        if not schedule_slot_keys:
            frequency_count = self.course_policy.read_frequency_count(
                medication.daily_frequency
            )
            schedule_slot_keys = medication_schedule_slot_keys_for_frequency(
                frequency_count
            )
        return {
            "medication_id": int(medication.id),
            "medication_name": str(medication.item_name).strip(),
            "image_url": safe_medication_image_url(medication.image_url),
            "dosage_per_time": (medication.dosage_per_time or "").strip(),
            "schedule_slot_keys": schedule_slot_keys,
        }

    # 함수이름: _medication_detail_response
    # 함수역할: 저장 복약정보를 공통 약 상세 화면용 응답으로 변환한다.
    # 매개변수: medication - 권한이 확인된 환자 소유 약 정보
    # 반환값: 이미지 URL이 안전하게 보정된 상세정보 응답
    @staticmethod
    def _medication_detail_response(
        medication: _SavedMedication,
    ) -> dict[str, object]:
        """저장 복약정보를 공통 약 상세 화면이 읽을 수 있는 응답으로 변환한다."""
        return {
            "id": int(medication.id),
            "patient_hash": str(medication.patient_hash or ""),
            "created_date": (
                medication.created_date.isoformat()
                if medication.created_date
                else ""
            ),
            "prescription_date": (
                medication.prescription_date.isoformat()
                if medication.prescription_date
                else ""
            ),
            "item_seq": medication.item_seq or "",
            "item_name": medication.item_name or "",
            "efficacy": medication.efficacy or "",
            "use_method": medication.use_method or "",
            "warning_message": medication.warning_message or "",
            "dosage_per_time": medication.dosage_per_time or "",
            "daily_frequency": medication.daily_frequency or "",
            "total_days": medication.total_days or "",
            "image_url": safe_medication_image_url(medication.image_url),
            "ai_guide": medication.ai_guide or "",
        }

    @staticmethod
    def _other_participant(link: _PatientCaregiverLink, user_hash: str) -> str:
        """연동에서 현재 사용자 반대편 참여자의 hash를 반환한다."""
        if str(link.patient_hash) == user_hash:
            return str(link.caregiver_hash)
        return str(link.patient_hash)
