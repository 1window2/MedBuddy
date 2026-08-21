"""보호자 알림 트랜잭션 아웃박스를 추가한다.

Revision ID: 7d2e4f1a8c63
Revises: 0bc4a8d9e210
Create Date: 2026-08-21
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "7d2e4f1a8c63"
down_revision: str | None = "0bc4a8d9e210"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# 함수명: upgrade
# 역할:
# - 복약 완료와 같은 트랜잭션에서 보호자 알림 요청을 보존할 테이블을 만든다.
def upgrade() -> None:
    op.create_table(
        "caregiver_alert_outbox",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("event_key", sa.String(length=64), nullable=False),
        sa.Column("patient_hash", sa.String(), nullable=False),
        sa.Column("slot_key", sa.String(length=32), nullable=False),
        sa.Column("status", sa.String(length=16), server_default="pending", nullable=False),
        sa.Column("attempt_count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("available_at", sa.DateTime(), nullable=False),
        sa.Column("processing_started_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("sent_at", sa.DateTime(), nullable=True),
        sa.Column("last_error", sa.String(length=500), nullable=True),
        sa.ForeignKeyConstraint(
            ["patient_hash"],
            ["user_accounts.user_hash"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "event_key",
            name="uq_caregiver_alert_outbox_event_key",
        ),
    )
    op.create_index(
        "ix_caregiver_alert_outbox_id",
        "caregiver_alert_outbox",
        ["id"],
        unique=False,
    )
    op.create_index(
        "ix_caregiver_alert_outbox_event_key",
        "caregiver_alert_outbox",
        ["event_key"],
        unique=False,
    )
    op.create_index(
        "ix_caregiver_alert_outbox_patient_hash",
        "caregiver_alert_outbox",
        ["patient_hash"],
        unique=False,
    )
    op.create_index(
        "ix_caregiver_alert_outbox_status",
        "caregiver_alert_outbox",
        ["status"],
        unique=False,
    )
    op.create_index(
        "ix_caregiver_alert_outbox_available_at",
        "caregiver_alert_outbox",
        ["available_at"],
        unique=False,
    )


# 함수명: downgrade
# 역할:
# - 보호자 알림 아웃박스 테이블과 인덱스를 제거한다.
def downgrade() -> None:
    op.drop_index(
        "ix_caregiver_alert_outbox_available_at",
        table_name="caregiver_alert_outbox",
    )
    op.drop_index(
        "ix_caregiver_alert_outbox_status",
        table_name="caregiver_alert_outbox",
    )
    op.drop_index(
        "ix_caregiver_alert_outbox_patient_hash",
        table_name="caregiver_alert_outbox",
    )
    op.drop_index(
        "ix_caregiver_alert_outbox_event_key",
        table_name="caregiver_alert_outbox",
    )
    op.drop_index(
        "ix_caregiver_alert_outbox_id",
        table_name="caregiver_alert_outbox",
    )
    op.drop_table("caregiver_alert_outbox")
