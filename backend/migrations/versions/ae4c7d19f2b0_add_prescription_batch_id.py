"""Add prescription analysis batch identifiers.

Revision ID: ae4c7d19f2b0
Revises: 9d2f6c1a8b30
Create Date: 2026-08-21
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "ae4c7d19f2b0"
down_revision: str | None = "9d2f6c1a8b30"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# Function Name: upgrade
# Description:
# - Adds the analysis batch identifier used to keep separate same-day
#   prescriptions from being combined by the change radar.
# Returns:
# - None.
def upgrade() -> None:
    op.add_column(
        "saved_medications",
        sa.Column("prescription_batch_id", sa.String(length=64), nullable=True),
    )
    op.create_index(
        "ix_saved_medications_prescription_batch_id",
        "saved_medications",
        ["prescription_batch_id"],
        unique=False,
    )


# Function Name: downgrade
# Description:
# - Removes prescription batch indexing and storage.
# Returns:
# - None.
def downgrade() -> None:
    op.drop_index(
        "ix_saved_medications_prescription_batch_id",
        table_name="saved_medications",
    )
    op.drop_column("saved_medications", "prescription_batch_id")
