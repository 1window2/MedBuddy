# 파일명: f7a2c9e4b610_add_slot_check_action_capability.py
# 역할: 환자 복용 확인 버튼 지원을 기기별 명시적 기능 플래그로 저장한다.
"""기존 기기 알림을 보존하며 환자 복용 완료 버튼 지원을 명시적으로 등록한다."""
from alembic import op
import sqlalchemy as sa

revision = "f7a2c9e4b610"
down_revision = "e6b4d2a9f031"
branch_labels = None
depends_on = None


# 함수이름: upgrade
# 함수역할: supports_slot_check_actions 열이 없으면 기존 기기를 미지원 상태로 유지하며 추가한다.
# 매개변수: 없음. Alembic 연결을 사용한다.
# 반환값: None. 스키마 변경 오류는 전달한다.
def upgrade() -> None:
    columns = {item["name"] for item in sa.inspect(op.get_bind()).get_columns("device_push_tokens")}
    if "supports_slot_check_actions" not in columns:
        op.add_column("device_push_tokens", sa.Column(
            "supports_slot_check_actions", sa.Boolean(), nullable=False, server_default=sa.false(),
        ))


# 함수이름: downgrade
# 함수역할: batch 변경으로 복용 확인 버튼 지원 열과 저장된 플래그를 제거한다.
# 매개변수: 없음. Alembic 연결을 사용한다.
# 반환값: None. 스키마 변경 오류는 전달한다.
def downgrade() -> None:
    with op.batch_alter_table("device_push_tokens") as batch:
        batch.drop_column("supports_slot_check_actions")
