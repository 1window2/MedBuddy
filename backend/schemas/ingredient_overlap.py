# 파일명: ingredient_overlap.py
# 역할: 등록 전 약과 복약 목록의 성분 겹침 조회 요청·응답 DTO를 정의한다.

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from entities.patient_hash_entity import MAX_PATIENT_HASH_LENGTH

MAX_INGREDIENT_OVERLAP_ITEMS = 50
# 한 품목에 대해 알려 줄 다른 품목 수의 상한. 그 품목들과 겹친 성분은 모두 담는다.
MAX_INGREDIENT_OVERLAP_PARTNERS_PER_ITEM = 10

IngredientOverlapItemSeq = Annotated[
    str,
    StringConstraints(pattern=r"^[0-9]{1,32}$"),
]


# Class Name: IngredientOverlapRequest
# Role: Carries the product numbers of the medicines on one result screen.
# Responsibilities: Limit the check to 1 to 50 numeric product numbers and reject unknown fields.
# Attributes: patient_hash (str | None) is an optional selector that the server resolves to the caller's own scope; item_seqs (list[str]) are the product numbers.
class IngredientOverlapRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    patient_hash: str | None = Field(
        default=None,
        max_length=MAX_PATIENT_HASH_LENGTH,
    )
    item_seqs: list[IngredientOverlapItemSeq] = Field(
        min_length=1,
        max_length=MAX_INGREDIENT_OVERLAP_ITEMS,
    )


# Class Name: IngredientOverlapPartner
# Role: Names the other medicine that shares an ingredient.
# Responsibilities: Tell whether it is already in the medication list or on the same result screen, and whether it is the same product.
# Attributes: item_seq and item_name (str) identify the product; source is "saved" or "batch"; same_product (bool) marks the same product number.
class IngredientOverlapPartner(BaseModel):
    item_seq: str
    item_name: str
    source: Literal["saved", "batch"]
    same_product: bool = False


# Class Name: IngredientOverlap
# Role: One shared ingredient between a checked medicine and one other medicine.
# Responsibilities: Pair the ingredient code and name with the other medicine.
# Attributes: ingredient_code and ingredient_name (str) come from the local approval catalog; with_ (IngredientOverlapPartner) is serialized as "with".
class IngredientOverlap(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    ingredient_code: str
    ingredient_name: str
    with_: IngredientOverlapPartner = Field(alias="with")


# Class Name: IngredientOverlapItem
# Role: Overlaps of one checked product number.
# Responsibilities: Name at most MAX_INGREDIENT_OVERLAP_PARTNERS_PER_ITEM other products, with every ingredient shared with each.
# Attributes: item_seq (str) is the checked product; overlaps (list[IngredientOverlap]) may be empty.
class IngredientOverlapItem(BaseModel):
    item_seq: str
    overlaps: list[IngredientOverlap] = Field(default_factory=list)


# Class Name: IngredientOverlapResponse
# Role: Result of one ingredient-overlap check.
# Responsibilities: Return one item per distinct requested product number in request order.
# Attributes: success (bool) is always true for a completed check; items (list[IngredientOverlapItem]) holds the results.
class IngredientOverlapResponse(BaseModel):
    success: bool = True
    items: list[IngredientOverlapItem] = Field(default_factory=list)
