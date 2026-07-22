# 파일명: check_prescription_change_control.py
# 역할: 현재 처방과 최근 90일 안의 관련 이전 처방을 비교한다.

import re
from collections.abc import Iterable
from datetime import date, timedelta

from sqlalchemy.orm import Session

from entities.medication_detail_entity import _DrugApprovalInfo
from entities.patient_hash_entity import normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication
from schemas.prescription_change import (
    PrescriptionChangeMedication,
    PrescriptionChangeRequest,
    PrescriptionChangeResponse,
    PrescriptionChangeSummary,
    PrescriptionMedicationChange,
    PrescriptionScheduleSnapshot,
)
from services.prescription_similarity import (
    PRESCRIPTION_COMPARISON_WINDOW_DAYS,
    PrescriptionSimilarityMedication,
    PrescriptionSimilarityService,
)


# 클래스명: CheckPrescriptionChange
# 역할: 저장된 이전 처방과 새로 분석한 현재 처방의 객관적 차이를 계산한다.
# 주요 책임:
#   - 환자 범위와 90일 비교 기간을 기준으로 이전 처방 후보를 조회한다.
#   - 약품, 성분과 치료 맥락 관련성이 가장 높은 후보를 선택한다.
#   - 품목 식별자와 정규화된 약품명으로 같은 약품을 연결한다.
#   - 추가, 이번 처방 미확인, 복약 일정 변경을 구분한다.
# 속성:
#   - db: 저장된 복약 정보를 조회하는 SQLAlchemy 세션
class CheckPrescriptionChange:
    _SPACE_PATTERN = re.compile(r"\s+")
    _NON_NAME_PATTERN = re.compile(r"[^0-9a-z가-힣]")
    _SCHEDULE_FIELDS = (
        "dosage_per_time",
        "daily_frequency",
        "total_days",
    )

    def __init__(
        self,
        db: Session,
        similarity_service: PrescriptionSimilarityService | None = None,
    ) -> None:
        self.db = db
        self.similarity_service = similarity_service or PrescriptionSimilarityService()

    # 함수이름: request_prescription_change
    # 함수역할:
    # - 현재 처방과 최근의 관련 이전 처방을 비교해 변화 요약을 생성한다.
    # - 관련 처방이 없거나 비교 기간을 지났으면 빈 변화 결과를 반환한다.
    # 매개변수:
    # - request: 환자 정보와 현재 처방 약품 목록
    # 반환값:
    # - 처방 변화 요약과 약품별 변화 목록
    def request_prescription_change(
        self,
        request: PrescriptionChangeRequest,
    ) -> PrescriptionChangeResponse:
        patient_hash = normalize_patient_hash(request.patient_hash)
        (
            comparison_status,
            previous_date,
            previous_medications,
            similarity_score,
            match_basis,
        ) = self._select_related_prescription(
            patient_hash,
            request.prescription_date,
            request.medications,
        )
        if previous_date is None:
            return PrescriptionChangeResponse(
                has_previous_prescription=False,
                comparison_status=comparison_status,
                comparison_window_days=PRESCRIPTION_COMPARISON_WINDOW_DAYS,
                current_prescription_date=request.prescription_date,
                summary=PrescriptionChangeSummary(),
            )

        changes, unchanged_count = self._compare_medications(
            previous_medications,
            request.medications,
        )
        return PrescriptionChangeResponse(
            has_previous_prescription=True,
            comparison_status="comparable",
            comparison_window_days=PRESCRIPTION_COMPARISON_WINDOW_DAYS,
            similarity_score=similarity_score,
            match_basis=match_basis,
            previous_prescription_date=previous_date,
            current_prescription_date=request.prescription_date,
            summary=self._build_summary(changes, unchanged_count),
            changes=changes,
        )

    # 함수이름: _select_related_prescription
    # 함수역할:
    # - 최근 비교 기간 안의 이전 처방들을 관련성 점수로 평가한다.
    # - 관련성이 확인된 후보 중 점수가 가장 높은 처방을 비교 기준으로 선택한다.
    # 매개변수:
    # - patient_hash: 조회 범위를 제한하는 환자 해시
    # - current_date: 현재 분석 중인 처방의 조제일자
    # - current_medications: 현재 분석한 처방 약품 목록
    # 반환값:
    # - 비교 상태, 선택한 날짜와 약품 목록, 유사도 점수와 판정 근거
    def _select_related_prescription(
        self,
        patient_hash: str,
        current_date: date | None,
        current_medications: list[PrescriptionChangeMedication],
    ) -> tuple[str, date | None, list[_SavedMedication], float | None, str]:
        history_status, candidates = self._load_candidate_prescriptions(
            patient_hash,
            current_date,
        )
        if not candidates:
            return history_status, None, [], None, ""

        ingredient_by_sequence = self._load_main_ingredients(
            current_medications,
            [medication for _, medications in candidates for medication in medications],
        )
        current_similarity_medications = self._to_similarity_medications(
            current_medications,
            ingredient_by_sequence,
        )
        related_candidates: list[
            tuple[float, date, list[_SavedMedication], str]
        ] = []
        for candidate_date, candidate_medications in candidates:
            result = self.similarity_service.compare(
                self._to_similarity_medications(
                    candidate_medications,
                    ingredient_by_sequence,
                ),
                current_similarity_medications,
            )
            if result.is_related:
                related_candidates.append(
                    (
                        result.score,
                        candidate_date,
                        candidate_medications,
                        result.match_basis,
                    )
                )

        if not related_candidates:
            return "unrelated", None, [], None, ""

        score, selected_date, selected_medications, match_basis = max(
            related_candidates,
            key=lambda candidate: (candidate[0], candidate[1]),
        )
        return (
            "comparable",
            selected_date,
            selected_medications,
            score,
            match_basis,
        )

    # 함수이름: _load_candidate_prescriptions
    # 함수역할:
    # - 같은 환자의 과거 처방을 날짜별로 묶고 최근 90일 후보만 반환한다.
    # - 과거 기록 자체가 없는 경우와 비교 기간을 지난 경우를 구분한다.
    # 매개변수:
    # - patient_hash: 조회 범위를 제한하는 환자 해시
    # - current_date: 현재 분석 중인 처방의 조제일자
    # 반환값:
    # - 기록 상태와 날짜별 이전 처방 후보 목록
    def _load_candidate_prescriptions(
        self,
        patient_hash: str,
        current_date: date | None,
    ) -> tuple[str, list[tuple[date, list[_SavedMedication]]]]:
        rows = (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == patient_hash)
            .order_by(
                _SavedMedication.prescription_date.desc(),
                _SavedMedication.created_date.desc(),
                _SavedMedication.id.desc(),
            )
            .all()
        )
        dated_rows = [
            (self._effective_prescription_date(row), row)
            for row in rows
            if self._effective_prescription_date(row) is not None
        ]
        reference_date = current_date or date.today()
        previous_dates = sorted(
            {
                prescription_date
                for prescription_date, _ in dated_rows
                if (
                    prescription_date < current_date
                    if current_date is not None
                    else prescription_date <= reference_date
                )
            },
            reverse=True,
        )
        if not previous_dates:
            return "no_history", []

        window_start = reference_date - timedelta(
            days=PRESCRIPTION_COMPARISON_WINDOW_DAYS
        )
        candidate_dates = [
            prescription_date
            for prescription_date in previous_dates
            if prescription_date >= window_start
        ]
        if not candidate_dates:
            return "expired", []

        return (
            "candidate",
            [
                (
                    candidate_date,
                    [
                        row
                        for row_date, row in dated_rows
                        if row_date == candidate_date
                    ],
                )
                for candidate_date in candidate_dates
            ],
        )

    # 함수이름: _load_main_ingredients
    # 함수역할:
    # - 로컬 의약품 허가정보에서 비교 후보 약품의 주성분을 한 번에 조회한다.
    # 매개변수:
    # - current_medications: 현재 처방 약품 목록
    # - previous_medications: 후보 이전 처방의 전체 약품 목록
    # 반환값:
    # - 품목 식별자별 주성분 문자열
    def _load_main_ingredients(
        self,
        current_medications: list[PrescriptionChangeMedication],
        previous_medications: list[_SavedMedication],
    ) -> dict[str, str]:
        item_sequences = {
            self._read_text(getattr(medication, "item_seq", ""))
            for medication in [*current_medications, *previous_medications]
            if self._read_text(getattr(medication, "item_seq", ""))
        }
        if not item_sequences:
            return {}

        rows = (
            self.db.query(_DrugApprovalInfo)
            .filter(_DrugApprovalInfo.item_seq.in_(item_sequences))
            .all()
        )
        return {
            self._read_text(row.item_seq): self._read_text(row.main_ingredient)
            for row in rows
            if self._read_text(row.item_seq)
        }

    # 함수이름: _to_similarity_medications
    # 함수역할:
    # - 저장 약품과 현재 요청 약품을 관련성 판정 전용 값 객체로 변환한다.
    # 매개변수:
    # - medications: 변환할 처방 약품 목록
    # - ingredient_by_sequence: 품목 식별자별 주성분
    # 반환값:
    # - 외부 저장소에 의존하지 않는 유사도 판정 입력 목록
    def _to_similarity_medications(
        self,
        medications: list[_SavedMedication] | list[PrescriptionChangeMedication],
        ingredient_by_sequence: dict[str, str],
    ) -> list[PrescriptionSimilarityMedication]:
        return [
            PrescriptionSimilarityMedication(
                item_seq=(item_sequence := self._read_text(
                    getattr(medication, "item_seq", "")
                )),
                item_name=self._read_text(getattr(medication, "item_name", "")),
                efficacy=self._read_text(getattr(medication, "efficacy", "")),
                main_ingredient=ingredient_by_sequence.get(item_sequence, ""),
            )
            for medication in medications
        ]

    # 함수이름: _compare_medications
    # 함수역할:
    # - 품목 식별자를 우선 사용하고 약품명을 보조 키로 사용해 처방 전후를 연결한다.
    # - 연결된 약은 복약 일정 변경을 확인하고, 연결되지 않은 약은 추가 또는 미확인으로 분류한다.
    # 매개변수:
    # - previous_medications: 이전 처방에 저장된 약품 목록
    # - current_medications: 현재 분석한 약품 목록
    # 반환값:
    # - 화면에 표시할 변화 목록과 변경 없는 약품 개수
    def _compare_medications(
        self,
        previous_medications: list[_SavedMedication],
        current_medications: list[PrescriptionChangeMedication],
    ) -> tuple[list[PrescriptionMedicationChange], int]:
        unmatched_previous = list(previous_medications)
        changes: list[PrescriptionMedicationChange] = []
        unchanged_count = 0

        for current in current_medications:
            previous = self._take_matching_previous(unmatched_previous, current)
            if previous is None:
                changes.append(self._build_added_change(current))
                continue

            changed_fields = self._changed_schedule_fields(previous, current)
            if not changed_fields:
                unchanged_count += 1
                continue
            changes.append(
                PrescriptionMedicationChange(
                    change_type="schedule_changed",
                    item_name=current.item_name,
                    changed_fields=changed_fields,
                    previous=self._snapshot(previous),
                    current=self._snapshot(current),
                )
            )

        changes.extend(
            PrescriptionMedicationChange(
                change_type="missing",
                item_name=previous.item_name or "약품명 확인 필요",
                previous=self._snapshot(previous),
            )
            for previous in unmatched_previous
        )
        return changes, unchanged_count

    # 함수이름: _take_matching_previous
    # 함수역할:
    # - 품목 식별자와 약품명 순서로 현재 약품에 대응하는 이전 약품을 찾는다.
    # - 일대일 비교를 위해 찾은 이전 약품은 미연결 목록에서 제거한다.
    # 매개변수:
    # - previous_medications: 아직 연결되지 않은 이전 처방 약품 목록
    # - current: 연결할 현재 처방 약품
    # 반환값:
    # - 연결된 이전 약품 또는 일치 항목이 없으면 None
    def _take_matching_previous(
        self,
        previous_medications: list[_SavedMedication],
        current: PrescriptionChangeMedication,
    ) -> _SavedMedication | None:
        current_sequence = current.item_seq.strip()
        if current_sequence:
            for index, previous in enumerate(previous_medications):
                if (previous.item_seq or "").strip() == current_sequence:
                    return previous_medications.pop(index)

        current_name = self._normalize_item_name(current.item_name)
        for index, previous in enumerate(previous_medications):
            if self._normalize_item_name(previous.item_name or "") == current_name:
                return previous_medications.pop(index)
        return None

    # 함수이름: _changed_schedule_fields
    # 함수역할:
    # - 이전 처방과 현재 처방에서 값이 달라진 복약 일정 필드명을 찾는다.
    # 매개변수:
    # - previous: 이전 처방의 저장 약품
    # - current: 현재 처방의 비교 약품
    # 반환값:
    # - 값이 달라진 필드명 목록
    def _changed_schedule_fields(
        self,
        previous: _SavedMedication,
        current: PrescriptionChangeMedication,
    ) -> list[str]:
        return [
            field_name
            for field_name in self._SCHEDULE_FIELDS
            if self._normalize_schedule_value(getattr(previous, field_name, ""))
            != self._normalize_schedule_value(getattr(current, field_name, ""))
        ]

    # 함수이름: _build_added_change
    # 함수역할:
    # - 현재 처방에만 존재하는 약품을 추가 변화 항목으로 변환한다.
    # 매개변수:
    # - current: 현재 처방의 비교 약품
    # 반환값:
    # - added 유형의 처방 변화 항목
    def _build_added_change(
        self,
        current: PrescriptionChangeMedication,
    ) -> PrescriptionMedicationChange:
        return PrescriptionMedicationChange(
            change_type="added",
            item_name=current.item_name,
            current=self._snapshot(current),
        )

    # 함수이름: _build_summary
    # 함수역할:
    # - 약품별 변화 목록을 유형별 개수로 집계한다.
    # 매개변수:
    # - changes: 약품별 처방 변화 목록
    # - unchanged_count: 변경되지 않은 약품 개수
    # 반환값:
    # - 처방 변화 유형별 요약
    def _build_summary(
        self,
        changes: Iterable[PrescriptionMedicationChange],
        unchanged_count: int,
    ) -> PrescriptionChangeSummary:
        change_list = list(changes)
        return PrescriptionChangeSummary(
            added_count=sum(item.change_type == "added" for item in change_list),
            missing_count=sum(item.change_type == "missing" for item in change_list),
            schedule_changed_count=sum(
                item.change_type == "schedule_changed" for item in change_list
            ),
            unchanged_count=unchanged_count,
        )

    # 함수이름: _snapshot
    # 함수역할:
    # - 저장 약품 또는 현재 비교 약품을 복약 일정 스냅샷으로 변환한다.
    # 매개변수:
    # - medication: 일정 값을 읽을 약품 객체
    # 반환값:
    # - 처방 전후 화면 표시에 사용하는 일정 스냅샷
    def _snapshot(
        self,
        medication: _SavedMedication | PrescriptionChangeMedication,
    ) -> PrescriptionScheduleSnapshot:
        return PrescriptionScheduleSnapshot(
            dosage_per_time=self._read_text(
                getattr(medication, "dosage_per_time", "")
            ),
            daily_frequency=self._read_text(
                getattr(medication, "daily_frequency", "")
            ),
            total_days=self._read_text(getattr(medication, "total_days", "")),
        )

    # 함수이름: _effective_prescription_date
    # 함수역할:
    # - 조제일자가 없을 때 등록일자를 비교 기준일로 사용한다.
    # 매개변수:
    # - medication: 저장된 약품 정보
    # 반환값:
    # - 비교에 사용할 처방 기준일
    def _effective_prescription_date(
        self,
        medication: _SavedMedication,
    ) -> date | None:
        return medication.prescription_date or medication.created_date

    # 함수이름: _normalize_item_name
    # 함수역할:
    # - 공백과 구두점을 제거해 약품명 비교 키를 생성한다.
    # 매개변수:
    # - item_name: 원본 약품명
    # 반환값:
    # - 정규화된 약품명
    def _normalize_item_name(self, item_name: str) -> str:
        compact_name = self._SPACE_PATTERN.sub("", item_name.strip().lower())
        return self._NON_NAME_PATTERN.sub("", compact_name)

    # 함수이름: _normalize_schedule_value
    # 함수역할:
    # - 복약 일정 값의 공백과 대소문자 차이를 제거한다.
    # 매개변수:
    # - value: 원본 복약 일정 값
    # 반환값:
    # - 비교용 복약 일정 문자열
    def _normalize_schedule_value(self, value: object) -> str:
        return self._SPACE_PATTERN.sub("", self._read_text(value).lower())

    # 함수이름: _read_text
    # 함수역할:
    # - 선택 필드 값을 안전한 문자열로 변환한다.
    # 매개변수:
    # - value: 문자열로 변환할 값
    # 반환값:
    # - 앞뒤 공백이 제거된 문자열
    def _read_text(self, value: object) -> str:
        return str(value or "").strip()
