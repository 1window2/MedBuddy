# 파일명: ab29d71c4e60_add_user_setting_revision.py
# 역할: 설정 변경의 낙관적 충돌 검사용 revision 열을 추가·제거한다.
"""사용자 설정의 지연 저장을 거절할 버전을 추가한다."""

from alembic import op
import sqlalchemy as sa

revision = "ab29d71c4e60"
down_revision = "f2c8a6d4e901"
branch_labels = None
depends_on = None


# 함수이름: upgrade
# 함수역할: 기존 설정도 버전 1로 시작하도록 필수 정수 revision 열을 추가한다.
# 매개변수: 없음. Alembic 연결을 사용한다.
# 반환값: None. 스키마 변경 오류는 Alembic으로 전달한다.
def upgrade() -> None:
    op.add_column(
        "user_settings",
        sa.Column("revision", sa.Integer(), nullable=False, server_default="1"),
    )


# 함수이름: downgrade
# 함수역할: batch 변경으로 설정 revision 열과 저장된 버전 값을 제거한다.
# 매개변수: 없음. Alembic 연결을 사용한다.
# 반환값: None. 스키마 변경 오류는 전달한다.
def downgrade() -> None:
    with op.batch_alter_table("user_settings") as batch_op:
        batch_op.drop_column("revision")
