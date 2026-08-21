"""저장 복약 정보에 사용자 확인 시간대를 추가한다.

Revision ID: e82bc4d1a930
Revises: d74a8e52f1c0
Create Date: 2026-07-29
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "e82bc4d1a930"
down_revision: str | None = "d74a8e52f1c0"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# 함수명: upgrade
# 역할:
# - 저장된 약마다 사용자가 확인한 복약 시간대 JSON을 보관할 열을 추가한다.
def upgrade() -> None:
    op.add_column(
        "saved_medications",
        sa.Column(
            "schedule_slot_keys",
            sa.Text(),
            server_default="[]",
            nullable=False,
        ),
    )


# 함수명: downgrade
# 역할:
# - 사용자 확인 복약 시간대 열을 제거한다.
def downgrade() -> None:
    op.drop_column("saved_medications", "schedule_slot_keys")
