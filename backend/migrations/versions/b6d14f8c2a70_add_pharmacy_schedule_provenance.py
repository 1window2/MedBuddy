"""Add pharmacy schedule provenance and persistent holiday caches.

Revision ID: b6d14f8c2a70
Revises: 8f2c6d4a1b90
Create Date: 2026-08-24
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "b6d14f8c2a70"
down_revision: str | None = "8f2c6d4a1b90"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "pharmacy_catalog_records",
        sa.Column(
            "official_designations",
            sa.JSON(),
            server_default=sa.text("'{}'"),
            nullable=False,
        ),
    )
    op.create_table(
        "pharmacy_holiday_fetches",
        sa.Column("schedule_date", sa.Date(), nullable=False),
        sa.Column("row_count", sa.Integer(), nullable=False),
        sa.Column(
            "fetched_at",
            sa.DateTime(),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("schedule_date"),
    )
    op.create_table(
        "pharmacy_holiday_schedules",
        sa.Column("schedule_date", sa.Date(), nullable=False),
        sa.Column("pharmacy_id", sa.String(length=32), nullable=False),
        sa.Column("start_time", sa.String(length=8), nullable=False),
        sa.Column("end_time", sa.String(length=8), nullable=False),
        sa.Column("note", sa.Text(), nullable=False),
        sa.Column(
            "fetched_at",
            sa.DateTime(),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("schedule_date", "pharmacy_id"),
    )
    op.create_table(
        "korean_holidays",
        sa.Column("holiday_date", sa.Date(), nullable=False),
        sa.Column(
            "fetched_at",
            sa.DateTime(),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("holiday_date"),
    )
    op.create_table(
        "korean_holiday_month_fetches",
        sa.Column("month_key", sa.String(length=7), nullable=False),
        sa.Column("row_count", sa.Integer(), nullable=False),
        sa.Column(
            "fetched_at",
            sa.DateTime(),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("month_key"),
    )


def downgrade() -> None:
    op.drop_table("korean_holiday_month_fetches")
    op.drop_table("korean_holidays")
    op.drop_table("pharmacy_holiday_schedules")
    op.drop_table("pharmacy_holiday_fetches")
    op.drop_column("pharmacy_catalog_records", "official_designations")
