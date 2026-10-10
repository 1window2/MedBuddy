# File Name: c5e1a7f3b902_add_catalog_refresh_state.py
# Role: Add the table that records when the periodic catalogue refresh last ran.

from alembic import op
import sqlalchemy as sa

revision = "c5e1a7f3b902"
down_revision = "b3a7d9e2f601"
branch_labels = None
depends_on = None


# Function Name: upgrade
# Description: Creates the refresh schedule table; it starts empty, which the refresh loop reads
#   as "never refreshed".
# Parameters: None. Returns: None.
def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    # A table already created by a local create_all is accepted as it is.
    if not inspector.has_table("catalog_refresh_state"):
        op.create_table(
            "catalog_refresh_state",
            sa.Column("name", sa.String(length=64), primary_key=True),
            sa.Column("last_attempt_at", sa.DateTime(), nullable=True),
            sa.Column("last_success_at", sa.DateTime(), nullable=True),
        )


# Function Name: downgrade
# Description: Removes only the schedule state; catalogue rows and user data are untouched.
# Parameters: None. Returns: None.
def downgrade() -> None:
    op.drop_table("catalog_refresh_state")
