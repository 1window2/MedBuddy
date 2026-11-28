# 파일명: photo_dose.py
# 역할: 사진으로 복용 기록의 계획 요청과 응답 형식을 검증한다.

from datetime import date
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

PhotoDoseSlotKey = Literal["morning", "lunch", "evening", "bedtime"]

# 관찰 이름은 알약 분석 결과의 영문 라벨이다. 길이만 제한하고 값 비교는 Control이 한다.
_Label = Annotated[str, Field(min_length=1, max_length=32, pattern=r"^[a-z_]+$")]
_ItemSeq = Annotated[str, Field(min_length=1, max_length=32, pattern=r"^[0-9A-Za-z]+$")]


# 클래스명: PhotoDosePill
# 역할: 사진에서 찾은 알약 하나의 후보 품목과 관찰한 모양·색을 담는다.
# 속성: index (int)는 분석 결과의 알약 번호, item_seqs는 후보 품목 번호, imprint_item_seqs는 그 가운데
#   각인이 맞은 후보, has_imprint는 알약에 2글자 이상의 각인이 보였는지, shape·colors는 관찰 라벨이다.
class PhotoDosePill(BaseModel):
    model_config = ConfigDict(extra="forbid")

    index: int = Field(ge=1, le=10)
    item_seqs: list[_ItemSeq] = Field(default_factory=list, max_length=100)
    imprint_item_seqs: list[_ItemSeq] = Field(default_factory=list, max_length=100)
    has_imprint: bool = False
    shape: _Label = "unknown"
    colors: list[_Label] = Field(default_factory=list, max_length=4)

    # 함수이름: validate_imprint_matches
    # 함수역할: 각인이 맞은 후보는 후보 목록 안에 있어야 한다.
    # 매개변수: 없음. 반환값: 현재 모델. 어긋나면 ValueError.
    @model_validator(mode="after")
    def validate_imprint_matches(self) -> "PhotoDosePill":
        if not set(self.imprint_item_seqs) <= set(self.item_seqs):
            raise ValueError("Imprint matches must be candidates of the same pill.")
        return self


# 클래스명: PhotoDoseAnswer
# 역할: 사용자가 "이 약이 OO인가요?"·"어떤 약인가요?"에 답한 결과다.
# 속성: index (int)는 알약 번호, medication_id (int | None)는 고른 약이며 None은 "기록하지 않기"다.
class PhotoDoseAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")

    index: int = Field(ge=1, le=10)
    medication_id: Annotated[int, Field(gt=0)] | None


# 클래스명: PhotoDosePlanRequest
# 역할: 계획 계산 입력. 사진은 받지 않는다.
# 주요 책임: 알약 번호와 답의 중복을 막는다.
class PhotoDosePlanRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    pills: list[PhotoDosePill] = Field(min_length=1, max_length=10)
    answers: list[PhotoDoseAnswer] = Field(default_factory=list, max_length=10)
    # 첫 계획이 돌려준 서명 토큰. 사진 시각을 담아 이후 계산의 시각을 고정한다.
    plan_token: str | None = Field(default=None, min_length=16, max_length=256, pattern=r"^[A-Za-z0-9_\-.]+$")

    # 함수이름: validate_indexes
    # 함수역할: 알약 번호가 겹치지 않고 답이 있는 알약을 가리키는지 확인한다.
    # 매개변수: 없음. 현재 모델을 검사한다.
    # 반환값: 현재 모델. 겹치거나 없는 번호는 ValueError다.
    @model_validator(mode="after")
    def validate_indexes(self) -> "PhotoDosePlanRequest":
        indexes = [pill.index for pill in self.pills]
        if len(set(indexes)) != len(indexes):
            raise ValueError("Pill indexes must be unique.")
        answered = [answer.index for answer in self.answers]
        if len(set(answered)) != len(answered) or not set(answered) <= set(indexes):
            raise ValueError("Answers must name distinct pills of this request.")
        return self


# 클래스명: PhotoDoseWriteGroup
# 역할: 앱이 확인 화면에 보여준 한 시간대의 기록 묶음이다.
class PhotoDoseWriteGroup(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schedule_date: date
    slot_key: PhotoDoseSlotKey
    medication_ids: list[Annotated[int, Field(gt=0)]] = Field(min_length=1, max_length=100)


# 클래스명: PhotoDoseExpectedWrite
# 역할: 앱이 확인 화면에 보여준 기록 전체다. 서버가 다시 계산한 결과와 같아야 기록한다.
class PhotoDoseExpectedWrite(BaseModel):
    model_config = ConfigDict(extra="forbid")

    groups: list[PhotoDoseWriteGroup] = Field(default_factory=list, max_length=8)
    as_needed_medication_ids: list[Annotated[int, Field(gt=0)]] = Field(default_factory=list, max_length=10)
    regimen_revisions: dict[
        Annotated[str, Field(pattern=r"^[1-9][0-9]{0,9}$")], Annotated[int, Field(ge=0)]
    ] = Field(default_factory=dict, max_length=100)


# 클래스명: PhotoDoseConfirmRequest
# 역할: 확인 버튼 요청. 계획 입력과 같고 작업 ID, 토큰, 기대한 기록을 더한다.
class PhotoDoseConfirmRequest(PhotoDosePlanRequest):
    operation_id: UUID
    plan_token: str = Field(min_length=16, max_length=256, pattern=r"^[A-Za-z0-9_\-.]+$")
    expected: PhotoDoseExpectedWrite
