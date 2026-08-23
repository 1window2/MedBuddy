# 파일명: 6e1b4a9c2d80_add_chat_medication_context.py
# 역할: 채팅 메시지에 전송 당시 약 정보 스냅샷을 보존한다.

"""채팅 메시지에 전송 당시 약 정보를 보존한다.

Revision ID: 6e1b4a9c2d80
Revises: 3a9f5c7d2e10
Create Date: 2026-08-23
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "6e1b4a9c2d80"
down_revision: str | None = "3a9f5c7d2e10"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_CHAT_MEDICATION_COLUMNS = {
    "medication_id": sa.Column("medication_id", sa.Integer(), nullable=True),
    "medication_name": sa.Column(
        "medication_name",
        sa.String(length=300),
        nullable=True,
    ),
    "medication_image_url": sa.Column(
        "medication_image_url",
        sa.Text(),
        nullable=True,
    ),
    "medication_dosage": sa.Column(
        "medication_dosage",
        sa.String(length=100),
        nullable=True,
    ),
}


# 함수이름: upgrade
# 함수역할: 기존 대화를 유지하면서 약 정보 스냅샷 열을 추가한다.
# 매개변수: 없음
# 반환값: 없음
def upgrade() -> None:
    """기존 대화를 유지하면서 약 정보 스냅샷 열을 추가한다."""
    inspector = sa.inspect(op.get_bind())
    if "chat_messages" not in inspector.get_table_names():
        raise RuntimeError("chat_messages table must exist before this migration.")
    existing_columns = {
        str(column["name"])
        for column in inspector.get_columns("chat_messages")
    }
    for column_name, column in _CHAT_MEDICATION_COLUMNS.items():
        if column_name not in existing_columns:
            op.add_column("chat_messages", column)


# 함수이름: downgrade
# 함수역할: 약 정보 스냅샷 열만 제거하고 기존 채팅 기록은 유지한다.
# 매개변수: 없음
# 반환값: 없음
def downgrade() -> None:
    """약 정보 스냅샷 열만 제거하고 기존 채팅 기록은 유지한다."""
    inspector = sa.inspect(op.get_bind())
    if "chat_messages" not in inspector.get_table_names():
        return
    existing_columns = {
        str(column["name"])
        for column in inspector.get_columns("chat_messages")
    }
    with op.batch_alter_table("chat_messages") as batch_op:
        for column_name in reversed(tuple(_CHAT_MEDICATION_COLUMNS)):
            if column_name in existing_columns:
                batch_op.drop_column(column_name)
