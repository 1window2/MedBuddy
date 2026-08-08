"""Persist the loose-pill reference catalog in the shared application database.

Revision ID: 0bc4a8d9e210
Revises: f93ac76b2e11
Create Date: 2026-07-30
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "0bc4a8d9e210"
down_revision: str | None = "f93ac76b2e11"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "pill_identification_references",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("item_seq", sa.String(), nullable=False),
        sa.Column("item_name", sa.String(), nullable=False),
        sa.Column("entp_name", sa.String(), nullable=True),
        sa.Column("image_url", sa.Text(), nullable=True),
        sa.Column("shape", sa.String(), nullable=True),
        sa.Column("color_primary", sa.String(), nullable=True),
        sa.Column("color_secondary", sa.String(), nullable=True),
        sa.Column("print_front", sa.String(), nullable=True),
        sa.Column("print_back", sa.String(), nullable=True),
        sa.Column("line_front", sa.String(), nullable=True),
        sa.Column("line_back", sa.String(), nullable=True),
        sa.Column(
            "updated_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    for column_name in (
        "item_seq",
        "item_name",
        "shape",
        "color_primary",
        "color_secondary",
        "print_front",
        "print_back",
    ):
        op.create_index(
            op.f(f"ix_pill_identification_references_{column_name}"),
            "pill_identification_references",
            [column_name],
            unique=column_name == "item_seq",
        )


def downgrade() -> None:
    op.drop_table("pill_identification_references")
