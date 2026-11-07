"""기존 기기 알림을 보존하며 환자 복용 완료 버튼 지원을 명시적으로 등록한다."""
from alembic import op
import sqlalchemy as sa

revision = "f7a2c9e4b610"
down_revision = "e6b4d2a9f031"
branch_labels = None
depends_on = None


def upgrade() -> None:
    columns = {item["name"] for item in sa.inspect(op.get_bind()).get_columns("device_push_tokens")}
    if "supports_slot_check_actions" not in columns:
        op.add_column("device_push_tokens", sa.Column(
            "supports_slot_check_actions", sa.Boolean(), nullable=False, server_default=sa.false(),
        ))


def downgrade() -> None:
    with op.batch_alter_table("device_push_tokens") as batch:
        batch.drop_column("supports_slot_check_actions")
