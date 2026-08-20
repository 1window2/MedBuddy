"""Add full-refresh markers to medication catalog rows.

Revision ID: 9d2f6c1a8b30
Revises: b71d8c2e4f10
Create Date: 2026-08-21
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "9d2f6c1a8b30"
down_revision: str | None = "b71d8c2e4f10"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# Function Name: upgrade
# Description:
# - Adds nullable refresh-generation markers used to prune records that have
#   disappeared from a successfully fetched complete MFDS dataset.
# Returns:
# - None.
def upgrade() -> None:
    op.add_column(
        "drug_basic_infos",
        sa.Column("catalog_sync_token", sa.String(length=36), nullable=True),
    )
    op.create_index(
        "ix_drug_basic_infos_catalog_sync_token",
        "drug_basic_infos",
        ["catalog_sync_token"],
        unique=False,
    )
    op.add_column(
        "drug_approval_infos",
        sa.Column("catalog_sync_token", sa.String(length=36), nullable=True),
    )
    op.create_index(
        "ix_drug_approval_infos_catalog_sync_token",
        "drug_approval_infos",
        ["catalog_sync_token"],
        unique=False,
    )


# Function Name: downgrade
# Description:
# - Removes the refresh-generation indexes and columns.
# Returns:
# - None.
def downgrade() -> None:
    op.drop_index(
        "ix_drug_approval_infos_catalog_sync_token",
        table_name="drug_approval_infos",
    )
    op.drop_column("drug_approval_infos", "catalog_sync_token")
    op.drop_index(
        "ix_drug_basic_infos_catalog_sync_token",
        table_name="drug_basic_infos",
    )
    op.drop_column("drug_basic_infos", "catalog_sync_token")
