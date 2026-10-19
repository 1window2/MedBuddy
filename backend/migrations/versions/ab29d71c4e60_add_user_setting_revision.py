"""사용자 설정의 지연 저장을 거절할 버전을 추가한다."""

from alembic import op
import sqlalchemy as sa

revision = "ab29d71c4e60"
down_revision = "f2c8a6d4e901"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "user_settings",
        sa.Column("revision", sa.Integer(), nullable=False, server_default="1"),
    )


def downgrade() -> None:
    with op.batch_alter_table("user_settings") as batch_op:
        batch_op.drop_column("revision")
