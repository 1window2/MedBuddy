"""Persist saved medication safety guidance.

Revision ID: 3f2a9c8d7e61
Revises: 7d2e4f1a8c63
Create Date: 2026-08-30
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "3f2a9c8d7e61"
down_revision: str | None = "7d2e4f1a8c63"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# Function Name: upgrade
# Description:
# - Adds the safety guidance returned by medication detail lookup to saved
#   medication snapshots so reopening a saved item retains the same guidance.
# Returns:
# - None.
def upgrade() -> None:
    with op.batch_alter_table("saved_medications") as batch_op:
        batch_op.add_column(sa.Column("interaction", sa.Text(), nullable=True))
        batch_op.add_column(sa.Column("side_effect", sa.Text(), nullable=True))
        batch_op.add_column(sa.Column("storage_method", sa.Text(), nullable=True))


# Function Name: downgrade
# Description:
# - Removes the saved medication safety guidance columns.
# Returns:
# - None.
def downgrade() -> None:
    with op.batch_alter_table("saved_medications") as batch_op:
        batch_op.drop_column("storage_method")
        batch_op.drop_column("side_effect")
        batch_op.drop_column("interaction")
