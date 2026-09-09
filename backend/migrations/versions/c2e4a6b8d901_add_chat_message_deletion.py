# 파일명: c2e4a6b8d901_add_chat_message_deletion.py
# 역할: 기존 메시지를 유지하며 환자·보호자 개인 숨김 시각과 전체 삭제 시각의 누락 열을 추가한다.
"""Add private message deletion and shared redaction markers.

Revision ID: c2e4a6b8d901
Revises: 9c4e7b2a6d10
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "c2e4a6b8d901"
down_revision: str = "9c4e7b2a6d10"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# 함수이름: upgrade
# 함수역할:
# - 기존 메시지를 유지하며 환자·보호자 개인 숨김 시각과 전체 삭제 시각의 누락 열을 추가한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
def upgrade() -> None:
    existing = {
        column["name"]
        for column in sa.inspect(op.get_bind()).get_columns("chat_messages")
    }
    for name in ("patient_deleted_at", "caregiver_deleted_at", "deleted_for_everyone_at"):
        if name not in existing:
            op.add_column("chat_messages", sa.Column(name, sa.DateTime(), nullable=True))


# 함수이름: downgrade
# 함수역할:
# - 메시지 삭제 표식 세 열을 제거한다. 전체 삭제로 이미 지운 본문·문맥은 복원하지 않는다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
def downgrade() -> None:
    with op.batch_alter_table("chat_messages") as batch_op:
        batch_op.drop_column("deleted_for_everyone_at")
        batch_op.drop_column("caregiver_deleted_at")
        batch_op.drop_column("patient_deleted_at")
