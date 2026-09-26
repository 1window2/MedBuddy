# 파일명: 4b7a9e2c6d80_add_caregiver_alias_to_links.py
# 역할: 기존 연결과 환자 별칭을 보존하며 환자 소유의 보호자 별칭 열을 추가한다.
from alembic import op
import sqlalchemy as sa

revision: str = "4b7a9e2c6d80"
down_revision: str | None = "c2a7e4d9f610"
branch_labels = None
depends_on = None


# 함수이름: upgrade
# 함수역할: 기존 행은 NULL로 유지하며 선택적인 보호자 별칭 열을 추가한다.
# 매개변수: 없음. 반환값: 없음.
def upgrade() -> None:
    columns = sa.inspect(op.get_bind()).get_columns("patient_caregiver_links")
    if "caregiver_alias" not in {column["name"] for column in columns}:
        op.add_column(
            "patient_caregiver_links",
            sa.Column("caregiver_alias", sa.String(length=20), nullable=True),
        )


# 함수이름: downgrade
# 함수역할: 이 변경이 추가한 보호자 별칭 열만 제거한다.
# 매개변수: 없음. 반환값: 없음.
def downgrade() -> None:
    with op.batch_alter_table("patient_caregiver_links") as batch_op:
        batch_op.drop_column("caregiver_alias")
