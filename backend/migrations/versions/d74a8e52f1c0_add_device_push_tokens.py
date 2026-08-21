"""FCM 기기 토큰 저장 테이블을 추가한다.

Revision ID: d74a8e52f1c0
Revises: c91f3a2b7d44
Create Date: 2026-07-29
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "d74a8e52f1c0"
down_revision: str | None = "c91f3a2b7d44"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# 함수이름: upgrade
# 함수역할:
# - 인증 사용자별 FCM 기기 토큰을 저장할 테이블과 인덱스를 추가한다.
# 반환값:
# - 없음
def upgrade() -> None:
    op.create_table(
        "device_push_tokens",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_hash", sa.String(), nullable=False),
        sa.Column("token", sa.String(), nullable=False),
        sa.Column(
            "platform",
            sa.String(),
            server_default="android",
            nullable=False,
        ),
        sa.Column(
            "enabled",
            sa.Boolean(),
            server_default=sa.true(),
            nullable=False,
        ),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token", name="uq_device_push_token_value"),
    )
    op.create_index(
        op.f("ix_device_push_tokens_id"),
        "device_push_tokens",
        ["id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_device_push_tokens_user_hash"),
        "device_push_tokens",
        ["user_hash"],
        unique=False,
    )


# 함수이름: downgrade
# 함수역할:
# - FCM 기기 토큰 테이블과 인덱스를 제거한다.
# 반환값:
# - 없음
def downgrade() -> None:
    op.drop_index(
        op.f("ix_device_push_tokens_user_hash"),
        table_name="device_push_tokens",
    )
    op.drop_index(
        op.f("ix_device_push_tokens_id"),
        table_name="device_push_tokens",
    )
    op.drop_table("device_push_tokens")
