# 파일명: 4b7a9e2c6d80_add_caregiver_alias_to_links.py
# 역할: 기존 연결과 환자 별칭을 보존하며 환자 소유의 보호자 별칭 열을 추가한다.
from alembic import op
import sqlalchemy as sa

revision: str = "4b7a9e2c6d80"
down_revision: str | None = "c2a7e4d9f610"
branch_labels = None
depends_on = None


# 함수이름: upgrade
# 함수역할: 환자·보호자 연결 테이블에 보호자 별칭 열이 없을 때만 추가하여 기존 별칭 데이터를 보존한다.
# 매개변수: 없음. Alembic의 현재 연결을 사용한다.
# 반환값: 없음. 스키마 변경 실패는 전파한다.
def upgrade() -> None:
    columns = sa.inspect(op.get_bind()).get_columns("patient_caregiver_links")
    if "caregiver_alias" not in {column["name"] for column in columns}:
        op.add_column(
            "patient_caregiver_links",
            sa.Column("caregiver_alias", sa.String(length=20), nullable=True),
        )


# 함수이름: downgrade
# 함수역할: 연결 테이블에서 보호자 별칭 열과 그 데이터를 배치 변경 방식으로 제거한다.
# 매개변수: 없음. Alembic의 현재 연결을 사용한다.
# 반환값: 없음. 스키마 변경 실패는 전파한다.
def downgrade() -> None:
    with op.batch_alter_table("patient_caregiver_links") as batch_op:
        batch_op.drop_column("caregiver_alias")
