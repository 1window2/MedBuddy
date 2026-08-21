"""Add retry-safe account deletion tombstones.

Revision ID: b71d8c2e4f10
Revises: 0bc4a8d9e210
Create Date: 2026-08-11
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "b71d8c2e4f10"
down_revision: str | None = "0bc4a8d9e210"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# Function Name: upgrade
# Description:
# - Adds durable markers for an account deletion request and external identity
#   deletion completion without rewriting existing user records.
# Returns:
# - None.
def upgrade() -> None:
    with op.batch_alter_table("user_accounts") as batch_op:
        batch_op.add_column(
            sa.Column("deletion_requested_at", sa.DateTime(), nullable=True)
        )
        batch_op.add_column(
            sa.Column("identity_deleted_at", sa.DateTime(), nullable=True)
        )


# Function Name: downgrade
# Description:
# - Removes the retry-safe account deletion markers.
# Returns:
# - None.
def downgrade() -> None:
    with op.batch_alter_table("user_accounts") as batch_op:
        batch_op.drop_column("identity_deleted_at")
        batch_op.drop_column("deletion_requested_at")