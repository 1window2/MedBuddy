# 파일명: 7c3d9e1f5a20_add_home_schedule_source.py
# 역할: 홈에 표시할 복약 일정의 사용자 선택을 저장한다.
from alembic import op
import sqlalchemy as sa

revision: str = "7c3d9e1f5a20"
down_revision: str | None = "4b7a9e2c6d80"
branch_labels = None
depends_on = None


# 함수이름: upgrade
# 함수역할: home_schedule_source 열이 없을 때만 기본값 self로 추가한다.
# 매개변수: 없음. Alembic의 현재 연결을 사용한다.
# 반환값: None. 기존 사용자 선택은 보존하고 DDL 오류는 전달한다.
def upgrade() -> None:
    columns = sa.inspect(op.get_bind()).get_columns("user_settings")
    if "home_schedule_source" not in {column["name"] for column in columns}:
        op.add_column(
            "user_settings",
            sa.Column("home_schedule_source", sa.String(), nullable=False, server_default="self"),
        )


# 함수이름: downgrade
# 함수역할: 다른 설정을 보존하면서 홈 일정 선택 열을 batch 변경으로 제거한다.
# 매개변수: 없음. Alembic의 현재 연결을 사용한다.
# 반환값: None. 저장된 홈 선택 값은 삭제되며 DDL 오류는 전달한다.
def downgrade() -> None:
    with op.batch_alter_table("user_settings") as batch_op:
        batch_op.drop_column("home_schedule_source")
