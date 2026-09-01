"""Merge the v0.2 feature schema with saved-medication safety fields.

Revision ID: 9c4e7b2a6d10
Revises: 3f2a9c8d7e61, 5e8a2c7d1f40
Create Date: 2026-09-01
"""

from collections.abc import Sequence


revision: str = "9c4e7b2a6d10"
down_revision: tuple[str, str] = ("3f2a9c8d7e61", "5e8a2c7d1f40")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


# Function Name: upgrade
# Description:
# - Joins the completed v0.1.1 safety migration and the v0.2 feature migration
#   chain without changing either published schema history.
# Returns:
# - None.
def upgrade() -> None:
    pass


# Function Name: downgrade
# Description:
# - Splits the merged migration history back into its two parent heads without
#   reverting either parent's schema changes.
# Returns:
# - None.
def downgrade() -> None:
    pass
