"""Opt in new Android clients without suppressing legacy OS notifications."""
from alembic import op
import sqlalchemy as sa

revision = "e4a19c7b520d"
down_revision = "7c3d9e1f5a20"
branch_labels = None
depends_on = None


def upgrade() -> None:
    columns = {item["name"] for item in sa.inspect(op.get_bind()).get_columns("device_push_tokens")}
    if "supports_caregiver_actions" not in columns:
        op.add_column("device_push_tokens", sa.Column(
            "supports_caregiver_actions", sa.Boolean(), nullable=False, server_default=sa.false(),
        ))


def downgrade() -> None:
    with op.batch_alter_table("device_push_tokens") as batch:
        batch.drop_column("supports_caregiver_actions")
