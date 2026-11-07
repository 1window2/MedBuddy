# File Name: f8a2c6d901be_merge_dose_sync_and_caregiver_actions.py
# Role: Joins the independently deployed dose-sync and caregiver-action migration branches.
"""Merge independently deployed dose-sync and caregiver-action schemas."""

revision = "f8a2c6d901be"
down_revision = ("a6e2d903bc71", "e4a19c7b520d")
branch_labels = None
depends_on = None


# Function Name: upgrade
# Description: Marks the merge point without repeating schema changes already made by either parent.
# Parameters: None.
# Returns: None; performs no DDL or data writes.
def upgrade() -> None:
    pass


# Function Name: downgrade
# Description: Leaves parent schemas untouched because this merge revision introduces no schema changes.
# Parameters: None.
# Returns: None; Alembic handles any requested parent downgrades separately.
def downgrade() -> None:
    pass
