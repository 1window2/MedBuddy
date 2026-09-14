# 파일명: 7c3d9e1f5a20_add_home_schedule_source.py
# 역할: 홈에 표시할 복약 일정의 사용자 선택을 저장한다.
from alembic import op
import sqlalchemy as sa

revision: str = "7c3d9e1f5a20"
down_revision: str | None = "4b7a9e2c6d80"
branch_labels = None
depends_on = None


# 함수역할: 기존 사용자는 내 일정을 기본값으로 유지하며 열을 추가한다.
def upgrade() -> None:
    columns = sa.inspect(op.get_bind()).get_columns("user_settings")
    if "home_schedule_source" not in {column["name"] for column in columns}:
        op.add_column(
            "user_settings",
            sa.Column("home_schedule_source", sa.String(), nullable=False, server_default="self"),
        )


# 함수역할: 다른 설정은 보존하고 홈 일정 선택 열만 제거한다.
def downgrade() -> None:
    with op.batch_alter_table("user_settings") as batch_op:
        batch_op.drop_column("home_schedule_source")
