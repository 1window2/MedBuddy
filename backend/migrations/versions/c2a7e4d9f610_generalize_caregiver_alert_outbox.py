# 파일명: c2a7e4d9f610_generalize_caregiver_alert_outbox.py
# 역할: 보호자 알림 아웃박스를 서버 주도 미복약 이벤트에도 사용할 수 있게 확장한다.
"""Generalize the caregiver alert outbox for missed-dose events.

Revision ID: c2a7e4d9f610
Revises: c2e4a6b8d901
Create Date: 2026-09-09
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "c2a7e4d9f610"
down_revision: str | None = "c2e4a6b8d901"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# 함수이름: upgrade
# 함수역할: 기존 아웃박스에 보호자, 이벤트 유형, 복약 날짜 열과 조회 인덱스를 추가한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
def upgrade() -> None:
    op.add_column(
        "caregiver_alert_outbox",
        sa.Column("caregiver_hash", sa.String(), nullable=True),
    )
    op.add_column(
        "caregiver_alert_outbox",
        sa.Column(
            "event_type",
            sa.String(length=32),
            server_default="dose_completed",
            nullable=False,
        ),
    )
    op.add_column(
        "caregiver_alert_outbox",
        sa.Column("schedule_date", sa.Date(), nullable=True),
    )
    op.create_index(
        "ix_caregiver_alert_outbox_caregiver_hash",
        "caregiver_alert_outbox",
        ["caregiver_hash"],
        unique=False,
    )
    op.create_index(
        "ix_caregiver_alert_outbox_schedule_date",
        "caregiver_alert_outbox",
        ["schedule_date"],
        unique=False,
    )


# 함수이름: downgrade
# 함수역할: 미복약 이벤트용 인덱스와 열을 역순으로 제거한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음.
def downgrade() -> None:
    op.drop_index(
        "ix_caregiver_alert_outbox_schedule_date",
        table_name="caregiver_alert_outbox",
    )
    op.drop_index(
        "ix_caregiver_alert_outbox_caregiver_hash",
        table_name="caregiver_alert_outbox",
    )
    op.drop_column("caregiver_alert_outbox", "schedule_date")
    op.drop_column("caregiver_alert_outbox", "event_type")
    op.drop_column("caregiver_alert_outbox", "caregiver_hash")
