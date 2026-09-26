# File Name: b3a7d9e2f601_add_chat_notification_jobs.py
# Role: Add an empty durable delivery queue; never backfill historical chat alerts.

from alembic import op
import sqlalchemy as sa

revision = "b3a7d9e2f601"
down_revision = "6d4f8a2c9301"
branch_labels = None
depends_on = None


# Function Name: upgrade
# Description: Add a message-owned queue with cascade cleanup and a due-work index.
# Parameters: None. Returns: None.
def upgrade() -> None:
    op.create_table(
        "chat_notification_jobs",
        sa.Column("message_id", sa.Integer(), sa.ForeignKey("chat_messages.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("recipient_hash", sa.String(), sa.ForeignKey("user_accounts.user_hash", ondelete="CASCADE"), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("available_at", sa.DateTime(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("last_error", sa.String(100), nullable=True),
    )
    op.create_index("ix_chat_notification_jobs_due", "chat_notification_jobs", ["status", "available_at"])


# Function Name: downgrade
# Description: Remove delivery jobs only; messages, links and medication records remain.
# Parameters: None. Returns: None.
def downgrade() -> None:
    op.drop_table("chat_notification_jobs")
