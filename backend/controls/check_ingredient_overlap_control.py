# 파일명: check_ingredient_overlap_control.py
# 역할: 등록 전 약의 주성분이 복용 중인 저장 약이나 같은 결과 화면의 다른 약과 겹치는지 로컬 허가정보로 확인한다.

from datetime import timedelta

from sqlalchemy.orm import Session

from core.application_clock import application_today
from entities.patient_hash_entity import normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication
from repositories.saved_medication_repository import SavedMedicationRepository
from schemas.ingredient_overlap import (
    MAX_INGREDIENT_OVERLAP_PARTNERS_PER_ITEM,
    IngredientOverlap,
    IngredientOverlapItem,
    IngredientOverlapPartner,
    IngredientOverlapResponse,
)
from services.medication_course_policy import (
    MAX_MEDICATION_COURSE_DAYS,
    MedicationCoursePolicy,
)
from services.medication_ingredients import (
    load_catalog_item_names,
    load_main_ingredients,
    parse_ingredient_codes,
)


# Class Name: CheckIngredientOverlap
# Role: Find shared main ingredients between medicines about to be registered and the owner's active medicines.
# Responsibilities:
# - Select saved medicines that are active today or later, counting a scheduled replacement pair once.
# - Report the same product already in the list, shared ingredients with other saved products, and shared ingredients between products on the same result screen.
# - Read only drug_approval_infos.main_ingredient (and item_name for batch partners); no AI or external call.
# Attributes: db is the request session; medication_repository reads saved medicines; course_policy decides active courses.
class CheckIngredientOverlap:
    # 함수이름: __init__
    # 함수역할:
    # - 요청 세션과 저장 약 저장소, 복용 기간 규칙을 준비한다.
    # 매개변수:
    # - db (Session): 현재 요청의 SQLAlchemy 세션.
    # - medication_repository (SavedMedicationRepository | None): 환자 소유 저장 약 저장소.
    # - course_policy (MedicationCoursePolicy | None): 활성 복용 기간 판정 규칙.
    # 반환값:
    # - 없음.
    def __init__(
        self,
        db: Session,
        medication_repository: SavedMedicationRepository | None = None,
        course_policy: MedicationCoursePolicy | None = None,
    ) -> None:
        self.db = db
        self.medication_repository = (
            medication_repository or SavedMedicationRepository(db)
        )
        self.course_policy = course_policy or MedicationCoursePolicy()

    # Function Name: request_ingredient_overlap
    # Description:
    # - Checks each distinct requested product number against the owner's active saved medicines and the other requested products.
    # - A saved row of the same product is reported once with same_product true; other saved or batch products are reported once per shared ingredient.
    # Parameters:
    # - patient_hash (str): Server-authorized owner scope.
    # - item_seqs (list[str]): Validated product numbers of the result screen.
    # Returns:
    # - IngredientOverlapResponse with one item per distinct product number in request order; database errors propagate.
    def request_ingredient_overlap(
        self,
        patient_hash: str,
        item_seqs: list[str],
    ) -> IngredientOverlapResponse:
        requested = list(dict.fromkeys(seq.strip() for seq in item_seqs if seq.strip()))
        saved_products = self._active_saved_products(normalize_patient_hash(patient_hash))
        ingredients_by_seq = {
            seq: parse_ingredient_codes(text)
            for seq, text in load_main_ingredients(
                self.db, [*requested, *saved_products],
            ).items()
        }

        overlaps_by_seq: dict[str, list[IngredientOverlap]] = {}
        batch_partner_seqs: set[str] = set()
        for seq in requested:
            overlaps = self._saved_overlaps(seq, saved_products, ingredients_by_seq)
            for partner_seq in requested:
                # 이미 복약 목록에 있는 품목은 저장 약 안내 한 번으로 충분하다.
                if partner_seq == seq or partner_seq in saved_products:
                    continue
                shared = self._shared_ingredients(
                    ingredients_by_seq.get(seq, {}),
                    ingredients_by_seq.get(partner_seq, {}),
                )
                if shared:
                    batch_partner_seqs.add(partner_seq)
                for code, name in shared:
                    overlaps.append(self._overlap(code, name, partner_seq, "", "batch"))
            overlaps_by_seq[seq] = self._cap_partners(overlaps)

        # 결과 화면의 다른 약 이름은 허가정보 품목명으로 채운다. 겹침이 있을 때만 조회한다.
        batch_names = load_catalog_item_names(self.db, batch_partner_seqs)
        items = []
        for seq in requested:
            for overlap in overlaps_by_seq[seq]:
                if overlap.with_.source == "batch":
                    overlap.with_.item_name = batch_names.get(overlap.with_.item_seq, "")
            items.append(IngredientOverlapItem(item_seq=seq, overlaps=overlaps_by_seq[seq]))
        return IngredientOverlapResponse(items=items)

    # Function Name: _active_saved_products
    # Description:
    # - Keeps saved medicines whose course overlaps today through the longest possible course, one row per product number.
    # - A scheduled replacement keeps both rows active until its effective date; the row that has not been superseded wins.
    # Parameters:
    # - patient_hash (str): Normalized owner scope.
    # Returns:
    # - dict[str, _SavedMedication] by product number in saved order.
    def _active_saved_products(self, patient_hash: str) -> dict[str, _SavedMedication]:
        today = application_today()
        window_end = today + timedelta(days=MAX_MEDICATION_COURSE_DAYS)
        products: dict[str, _SavedMedication] = {}
        for medication in self.medication_repository.list_ingredient_check_medications(
            patient_hash,
        ):
            seq = str(medication.item_seq or "").strip()
            if not seq or not self.course_policy.is_active_during(
                medication, today, window_end,
            ):
                continue
            current = products.get(seq)
            if current is None or (
                current.superseded_by_id is not None
                and medication.superseded_by_id is None
            ):
                products[seq] = medication
        return products

    # Function Name: _saved_overlaps
    # Description: Lists the same product once, then each ingredient shared with another active saved product.
    # Parameters: seq (str) is the checked product; saved_products and ingredients_by_seq are the loaded data.
    # Returns: list[IngredientOverlap] in saved order, same products first.
    def _saved_overlaps(
        self,
        seq: str,
        saved_products: dict[str, _SavedMedication],
        ingredients_by_seq: dict[str, dict[str, str]],
    ) -> list[IngredientOverlap]:
        own = ingredients_by_seq.get(seq, {})
        same: list[IngredientOverlap] = []
        shared_entries: list[IngredientOverlap] = []
        for saved_seq, medication in saved_products.items():
            item_name = str(medication.item_name or "").strip()
            if saved_seq == seq:
                code, name = next(iter(own.items()), ("", ""))
                same.append(
                    self._overlap(code, name, saved_seq, item_name, "saved", same_product=True)
                )
                continue
            for code, name in self._shared_ingredients(own, ingredients_by_seq.get(saved_seq, {})):
                shared_entries.append(self._overlap(code, name, saved_seq, item_name, "saved"))
        return [*same, *shared_entries]

    # Function Name: _shared_ingredients
    # Description: Intersects two parsed ingredient maps by code in the checked product's order.
    # Parameters: own and other (dict[str, str]) are parsed ingredient codes and names.
    # Returns: list of (code, name); the checked product's name is used unless it is empty.
    @staticmethod
    def _shared_ingredients(
        own: dict[str, str],
        other: dict[str, str],
    ) -> list[tuple[str, str]]:
        return [
            (code, name or other.get(code, ""))
            for code, name in own.items()
            if code in other
        ]

    # Function Name: _cap_partners
    # Description: Keeps the entries of the first MAX_INGREDIENT_OVERLAP_PARTNERS_PER_ITEM other products, with every ingredient shared with each.
    # Parameters: overlaps (list[IngredientOverlap]) are one item's entries in report order.
    # Returns: list[IngredientOverlap] in the same order.
    @staticmethod
    def _cap_partners(overlaps: list[IngredientOverlap]) -> list[IngredientOverlap]:
        # 성분 수가 아니라 다른 품목 수로 자른다. 복합제끼리는 품목 하나에 여러 성분이 겹쳐서
        # 항목 수로 자르면 뒤쪽 품목이 통째로 빠지고 안내의 "외 N개"가 줄어든다.
        partners: set[tuple[str, str]] = set()
        kept: list[IngredientOverlap] = []
        for overlap in overlaps:
            partner = (overlap.with_.source, overlap.with_.item_seq)
            if partner not in partners:
                if len(partners) >= MAX_INGREDIENT_OVERLAP_PARTNERS_PER_ITEM:
                    continue
                partners.add(partner)
            kept.append(overlap)
        return kept

    # Function Name: _overlap
    # Description: Builds one overlap entry.
    # Parameters: code and name describe the ingredient; partner_seq, partner_name and source describe the other medicine; same_product marks the same product number.
    # Returns: IngredientOverlap.
    @staticmethod
    def _overlap(
        code: str,
        name: str,
        partner_seq: str,
        partner_name: str,
        source: str,
        *,
        same_product: bool = False,
    ) -> IngredientOverlap:
        return IngredientOverlap(
            ingredient_code=code,
            ingredient_name=name,
            with_=IngredientOverlapPartner(
                item_seq=partner_seq,
                item_name=partner_name,
                source=source,
                same_product=same_product,
            ),
        )
