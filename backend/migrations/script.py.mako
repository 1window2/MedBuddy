<%doc>
File Name: script.py.mako
Role: Generates Alembic revision modules with metadata and documented migration entry points.
</%doc>
"""${message}

Revision ID: ${up_revision}
Revises: ${down_revision | comma,n}
Create Date: ${create_date}
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa
${imports if imports else ""}

revision: str = ${repr(up_revision)}
down_revision: str | Sequence[str] | None = ${repr(down_revision)}
branch_labels: str | Sequence[str] | None = ${repr(branch_labels)}
depends_on: str | Sequence[str] | None = ${repr(depends_on)}


# Function Name: upgrade
# Description: Applies the schema operations generated for this revision.
# Parameters: None; Alembic supplies the active database connection.
# Returns: None; database operation failures propagate to Alembic.
def upgrade() -> None:
    ${upgrades if upgrades else "pass"}


# Function Name: downgrade
# Description: Runs the reverse schema operations generated for this revision.
# Parameters: None; Alembic supplies the active database connection.
# Returns: None; irreversible data changes are not restored automatically.
def downgrade() -> None:
    ${downgrades if downgrades else "pass"}
