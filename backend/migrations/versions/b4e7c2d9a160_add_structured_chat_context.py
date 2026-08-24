# 파일명: b4e7c2d9a160_add_structured_chat_context.py
# 역할: 채팅 메시지에 서버 검증형 구조화 문맥을 저장할 열을 추가한다.

"""채팅 메시지 종류와 구조화 문맥을 추가한다.

Revision ID: b4e7c2d9a160
Revises: b6d14f8c2a70
Create Date: 2026-08-24
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "b4e7c2d9a160"
down_revision: str | None = "b6d14f8c2a70"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_STRUCTURED_CHAT_COLUMNS = {
    "message_kind": sa.Column(
        "message_kind",
        sa.String(length=40),
        nullable=False,
        server_default="text",
    ),
    "context_payload": sa.Column("context_payload", sa.JSON(), nullable=True),
}


def upgrade() -> None:
    """기존 텍스트 메시지를 유지하면서 구조화 문맥 열을 추가한다."""
    inspector = sa.inspect(op.get_bind())
    if "chat_messages" not in inspector.get_table_names():
        raise RuntimeError("chat_messages table must exist before this migration.")
    existing_columns = {
        str(column["name"])
        for column in inspector.get_columns("chat_messages")
    }
    for column_name, column in _STRUCTURED_CHAT_COLUMNS.items():
        if column_name not in existing_columns:
            op.add_column("chat_messages", column)


def downgrade() -> None:
    """구조화 문맥 열만 제거하고 기존 채팅 데이터는 유지한다."""
    inspector = sa.inspect(op.get_bind())
    if "chat_messages" not in inspector.get_table_names():
        return
    existing_columns = {
        str(column["name"])
        for column in inspector.get_columns("chat_messages")
    }
    with op.batch_alter_table("chat_messages") as batch_op:
        for column_name in reversed(tuple(_STRUCTURED_CHAT_COLUMNS)):
            if column_name in existing_columns:
                batch_op.drop_column(column_name)
