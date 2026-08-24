"""Add the normalized nationwide pharmacy catalogue.

Revision ID: 8f2c6d4a1b90
Revises: 6e1b4a9c2d80
Create Date: 2026-08-24
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "8f2c6d4a1b90"
down_revision: str | None = "6e1b4a9c2d80"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "pharmacy_catalog_records",
        sa.Column("pharmacy_id", sa.String(length=32), nullable=False),
        sa.Column("name", sa.String(length=300), nullable=False),
        sa.Column("address", sa.Text(), nullable=False),
        sa.Column("telephone", sa.String(length=80), nullable=False),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("weekly_hours", sa.JSON(), nullable=False),
        sa.Column(
            "source_updated_at",
            sa.DateTime(),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("pharmacy_id"),
    )
    op.create_index(
        "ix_pharmacy_catalog_records_name",
        "pharmacy_catalog_records",
        ["name"],
    )
    op.create_index(
        "ix_pharmacy_catalog_records_latitude",
        "pharmacy_catalog_records",
        ["latitude"],
    )
    op.create_index(
        "ix_pharmacy_catalog_records_longitude",
        "pharmacy_catalog_records",
        ["longitude"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_pharmacy_catalog_records_longitude",
        table_name="pharmacy_catalog_records",
    )
    op.drop_index(
        "ix_pharmacy_catalog_records_latitude",
        table_name="pharmacy_catalog_records",
    )
    op.drop_index(
        "ix_pharmacy_catalog_records_name",
        table_name="pharmacy_catalog_records",
    )
    op.drop_table("pharmacy_catalog_records")
