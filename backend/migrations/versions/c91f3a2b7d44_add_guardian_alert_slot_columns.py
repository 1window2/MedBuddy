"""보호자 시간대별 알림 설정 컬럼을 추가한다.

Revision ID: c91f3a2b7d44
Revises: a4f66c9a7d0b
Create Date: 2026-07-29
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "c91f3a2b7d44"
down_revision: str | None = "a4f66c9a7d0b"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# 함수이름: upgrade
# 함수역할:
# - 보호자별 아침·점심·저녁·취침 전 알림 설정을 저장할 컬럼을 추가한다.
# - 기존 단일 알림 설정은 새 시간대 설정을 만들 때 호환 데이터로 사용한다.
# 반환값:
# - 없음
def upgrade() -> None:
    with op.batch_alter_table("guardian_alert_settings") as batch_op:
        batch_op.add_column(sa.Column("deadline_hour", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("deadline_minute", sa.Integer(), nullable=True))
        batch_op.add_column(
            sa.Column(
                "slot_settings",
                sa.Text(),
                nullable=False,
                server_default="{}",
            )
        )


# 함수이름: downgrade
# 함수역할:
# - 시간대별 보호자 알림 설정 컬럼을 제거해 이전 스키마로 되돌린다.
# 반환값:
# - 없음
def downgrade() -> None:
    with op.batch_alter_table("guardian_alert_settings") as batch_op:
        batch_op.drop_column("slot_settings")
        batch_op.drop_column("deadline_minute")
        batch_op.drop_column("deadline_hour")
