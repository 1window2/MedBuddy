"""Add private message deletion and shared redaction markers.

Revision ID: c2e4a6b8d901
Revises: 9c4e7b2a6d10
"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa

revision: str = "c2e4a6b8d901"
down_revision: str = "9c4e7b2a6d10"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# Function Name: upgrade
# Description: Adds nullable deletion markers without changing existing messages.
# Returns: None.
def upgrade() -> None:
    existing = {
        column["name"]
        for column in sa.inspect(op.get_bind()).get_columns("chat_messages")
    }
    for name in ("patient_deleted_at", "caregiver_deleted_at", "deleted_for_everyone_at"):
        if name not in existing:
            op.add_column("chat_messages", sa.Column(name, sa.DateTime(), nullable=True))


# Function Name: downgrade
# Description: Removes markers; shared redacted content cannot be restored.
# Returns: None.
def downgrade() -> None:
    with op.batch_alter_table("chat_messages") as batch_op:
        batch_op.drop_column("deleted_for_everyone_at")
        batch_op.drop_column("caregiver_deleted_at")
        batch_op.drop_column("patient_deleted_at")
