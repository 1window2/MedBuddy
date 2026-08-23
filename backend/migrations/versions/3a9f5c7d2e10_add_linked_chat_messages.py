# 파일명: 3a9f5c7d2e10_add_linked_chat_messages.py
# 역할: 환자·보호자 연동별 채팅 메시지 테이블을 추가한다.

"""환자·보호자 연동별 채팅 메시지 테이블을 추가한다.

Revision ID: 3a9f5c7d2e10
Revises: 7d2e4f1a8c63
Create Date: 2026-08-23
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "3a9f5c7d2e10"
down_revision: str | None = "7d2e4f1a8c63"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_CHAT_MESSAGE_COLUMNS = {
    "id",
    "link_id",
    "sender_hash",
    "client_message_id",
    "body",
    "created_at",
    "read_at",
}

_CHAT_MESSAGE_INDEXES = {
    "ix_chat_messages_id": ["id"],
    "ix_chat_messages_link_id": ["link_id"],
    "ix_chat_messages_sender_hash": ["sender_hash"],
    "ix_chat_messages_created_at": ["created_at"],
}


# 함수이름: upgrade
# 함수역할: 채팅 저장, 읽음 상태와 재전송 중복 방지 구조를 추가한다.
# 매개변수: 없음
# 반환값: 없음
def upgrade() -> None:
    """채팅 저장, 읽음 상태, 재전송 중복 방지에 필요한 구조를 만든다."""
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    table_exists = "chat_messages" in inspector.get_table_names()
    if not table_exists:
        op.create_table(
            "chat_messages",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("link_id", sa.Integer(), nullable=False),
            sa.Column("sender_hash", sa.String(), nullable=False),
            sa.Column("client_message_id", sa.String(length=64), nullable=False),
            sa.Column("body", sa.Text(), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("read_at", sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(
                ["link_id"],
                ["patient_caregiver_links.id"],
                ondelete="CASCADE",
            ),
            sa.ForeignKeyConstraint(
                ["sender_hash"],
                ["user_accounts.user_hash"],
                ondelete="CASCADE",
            ),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint(
                "link_id",
                "sender_hash",
                "client_message_id",
                name="uq_chat_message_client_request",
            ),
        )
        existing_indexes: set[str] = set()
    else:
        _validate_existing_chat_table(inspector)
        existing_indexes = {
            str(index["name"])
            for index in inspector.get_indexes("chat_messages")
            if index.get("name")
        }

    for index_name, column_names in _CHAT_MESSAGE_INDEXES.items():
        if index_name not in existing_indexes:
            op.create_index(
                index_name,
                "chat_messages",
                column_names,
                unique=False,
            )


# 함수이름: downgrade
# 함수역할: 채팅 메시지 테이블과 관련 인덱스를 제거한다.
# 매개변수: 없음
# 반환값: 없음
def downgrade() -> None:
    """채팅 메시지 테이블과 관련 인덱스를 제거한다."""
    op.drop_index("ix_chat_messages_created_at", table_name="chat_messages")
    op.drop_index("ix_chat_messages_sender_hash", table_name="chat_messages")
    op.drop_index("ix_chat_messages_link_id", table_name="chat_messages")
    op.drop_index("ix_chat_messages_id", table_name="chat_messages")
    op.drop_table("chat_messages")


def _validate_existing_chat_table(inspector: sa.Inspector) -> None:
    """자동 생성된 기존 테이블이 이번 마이그레이션과 호환되는지 확인한다."""
    column_names = {
        str(column["name"])
        for column in inspector.get_columns("chat_messages")
    }
    missing_columns = _CHAT_MESSAGE_COLUMNS - column_names
    if missing_columns:
        missing = ", ".join(sorted(missing_columns))
        raise RuntimeError(
            f"Existing chat_messages table is incompatible; missing: {missing}"
        )

    unique_column_sets = {
        tuple(str(name) for name in constraint.get("column_names") or [])
        for constraint in inspector.get_unique_constraints("chat_messages")
    }
    expected_unique_columns = (
        "link_id",
        "sender_hash",
        "client_message_id",
    )
    if expected_unique_columns not in unique_column_sets:
        raise RuntimeError(
            "Existing chat_messages table is missing the idempotency constraint."
        )
