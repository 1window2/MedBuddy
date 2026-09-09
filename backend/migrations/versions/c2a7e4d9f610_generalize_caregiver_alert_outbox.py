"""Generalize the caregiver alert outbox for missed-dose events.

Revision ID: c2a7e4d9f610
Revises: 9c4e7b2a6d10
Create Date: 2026-09-09
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "c2a7e4d9f610"
down_revision: str | None = "9c4e7b2a6d10"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


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
