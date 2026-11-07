# 파일명: e6b4d2a9f031_scope_medication_care_receipts.py
# 역할: 약 변경 영수증에 소유 약 연결·삭제 표시를 추가하고 기존 응답을 안전하게 정리한다.
"""재전송 영수증을 약에 연결하고 삭제된 약의 응답은 최소 표식으로 바꾼다."""

import json

from alembic import op
import sqlalchemy as sa

revision = "e6b4d2a9f031"
down_revision = "c8d3e7a92104"
branch_labels = None
depends_on = None


# 함수이름: upgrade
# 함수역할: 약 ID·대체 ID·응답 삭제 열과 인덱스를 추가하고 500건씩 소유 약을 확인해 구버전 영수증을 연결한다.
# 매개변수: 없음. Alembic 연결의 기존 약·영수증을 읽는다.
# 반환값: None. 소유·대체 관계가 불명확한 응답은 비우고 DB 오류는 전달한다.
def upgrade() -> None:
    op.add_column("medication_care_operations", sa.Column("medication_id", sa.Integer(), nullable=True))
    op.add_column("medication_care_operations", sa.Column("replacement_medication_id", sa.Integer(), nullable=True))
    op.add_column("medication_care_operations", sa.Column(
        "response_redacted", sa.Boolean(), nullable=False, server_default=sa.false(),
    ))
    for name in ("medication_id", "replacement_medication_id"):
        op.create_index(f"ix_medication_care_operations_{name}", "medication_care_operations", [name])

    connection = op.get_bind()
    medications = sa.table(
        "saved_medications", sa.column("id", sa.Integer()), sa.column("patient_hash", sa.String()),
        sa.column("superseded_by_id", sa.Integer()),
    )
    receipts = sa.table(
        "medication_care_operations", sa.column("id", sa.Integer()), sa.column("patient_hash", sa.String()),
        sa.column("response_json", sa.Text()), sa.column("medication_id", sa.Integer()),
        sa.column("replacement_medication_id", sa.Integer()), sa.column("response_redacted", sa.Boolean()),
    )
    # 운영 데이터가 많아도 영수증 전체 응답을 한꺼번에 메모리에 올리지 않는다.
    last_id = 0
    while True:
        rows = connection.execute(sa.select(receipts).where(receipts.c.id > last_id).order_by(receipts.c.id).limit(500)).mappings().all()
        if not rows:
            break
        for row in rows:
            last_id = row["id"]
            try:
                payload = json.loads(row["response_json"])
            except (TypeError, ValueError):
                payload = None
            identifier = payload.get("medication_id", payload.get("id")) if isinstance(payload, dict) else None
            scoped_medications = sa.select(medications).where(medications.c.patient_hash == row["patient_hash"])
            medication = None
            if type(identifier) is int and identifier > 0:
                medication = connection.execute(scoped_medications.where(medications.c.id == identifier)).mappings().first()
            values = {"medication_id": None, "replacement_medication_id": None, "response_redacted": True, "response_json": "{}"}
            if medication is not None:
                values = {"medication_id": identifier, "replacement_medication_id": None, "response_redacted": False}
                if "medication_id" not in payload:
                    originals = connection.execute(scoped_medications.where(medications.c.superseded_by_id == identifier)).mappings().all()
                    if len(originals) == 1:
                        values.update(medication_id=originals[0]["id"], replacement_medication_id=identifier)
                    elif originals:
                        values = {"medication_id": None, "replacement_medication_id": None, "response_redacted": True, "response_json": "{}"}
            connection.execute(receipts.update().where(receipts.c.id == row["id"]).values(**values))


# 함수이름: downgrade
# 함수역할: 영수증 연결 인덱스와 열을 제거하되 이미 지운 건강정보는 복원하지 않는다.
# 매개변수: 없음. Alembic 연결을 사용한다.
# 반환값: None. DB 오류는 전달한다.
def downgrade() -> None:
    # 비운 건강정보는 복구하지 않는다. 구버전도 빈 성공 응답을 재실행하지 않고 반환한다.
    for name in ("medication_id", "replacement_medication_id"):
        op.drop_index(f"ix_medication_care_operations_{name}", table_name="medication_care_operations")
    for name in ("response_redacted", "replacement_medication_id", "medication_id"):
        op.drop_column("medication_care_operations", name)
