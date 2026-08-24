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
    """앱이 먼저 만든 로컬 테이블도 유지하며 약국 운영 근거를 추가한다."""
    inspector = sa.inspect(op.get_bind())
    table_names = set(inspector.get_table_names())
    if "pharmacy_catalog_records" not in table_names:
        raise RuntimeError(
            "pharmacy_catalog_records table must exist before this migration."
        )

    catalog_columns = {
        str(column["name"])
        for column in inspector.get_columns("pharmacy_catalog_records")
    }
    if "official_designations" not in catalog_columns:
        op.add_column(
            "pharmacy_catalog_records",
            sa.Column(
                "official_designations",
                sa.JSON(),
                server_default=sa.text("'{}'"),
                nullable=False,
            ),
        )
    if "pharmacy_holiday_fetches" not in table_names:
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
    if "pharmacy_holiday_schedules" not in table_names:
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
    if "korean_holidays" not in table_names:
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
    if "korean_holiday_month_fetches" not in table_names:
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
    """이번 버전에서 관리하는 표와 열이 있을 때만 제거한다."""
    inspector = sa.inspect(op.get_bind())
    table_names = set(inspector.get_table_names())
    for table_name in (
        "korean_holiday_month_fetches",
        "korean_holidays",
        "pharmacy_holiday_schedules",
        "pharmacy_holiday_fetches",
    ):
        if table_name in table_names:
            op.drop_table(table_name)

    if "pharmacy_catalog_records" not in table_names:
        return
    catalog_columns = {
        str(column["name"])
        for column in inspector.get_columns("pharmacy_catalog_records")
    }
    if "official_designations" in catalog_columns:
        op.drop_column("pharmacy_catalog_records", "official_designations")
