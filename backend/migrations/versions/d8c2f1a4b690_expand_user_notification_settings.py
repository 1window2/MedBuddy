# 파일명: d8c2f1a4b690_expand_user_notification_settings.py
# 역할: 사용자별 알림, 개인정보, 기본 복약 시각과 표시 설정을 저장한다.

"""사용자 알림 및 표시 설정 열을 추가한다.

Revision ID: d8c2f1a4b690
Revises: b4e7c2d9a160
Create Date: 2026-08-25
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "d8c2f1a4b690"
down_revision: str | None = "b4e7c2d9a160"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_SETTING_COLUMNS = {
    "language_mode": sa.Column(
        "language_mode",
        sa.String(),
        nullable=False,
        server_default="ko",
    ),
    "time_format": sa.Column(
        "time_format",
        sa.String(),
        nullable=False,
        server_default="24h",
    ),
    "medication_notifications_enabled": sa.Column(
        "medication_notifications_enabled",
        sa.Boolean(),
        nullable=False,
        server_default=sa.true(),
    ),
    "caregiver_notifications_enabled": sa.Column(
        "caregiver_notifications_enabled",
        sa.Boolean(),
        nullable=False,
        server_default=sa.true(),
    ),
    "chat_notifications_enabled": sa.Column(
        "chat_notifications_enabled",
        sa.Boolean(),
        nullable=False,
        server_default=sa.true(),
    ),
    "notification_detail_mode": sa.Column(
        "notification_detail_mode",
        sa.String(),
        nullable=False,
        server_default="full",
    ),
    "default_morning_time": sa.Column(
        "default_morning_time",
        sa.String(),
        nullable=False,
        server_default="08:00",
    ),
    "default_lunch_time": sa.Column(
        "default_lunch_time",
        sa.String(),
        nullable=False,
        server_default="12:00",
    ),
    "default_evening_time": sa.Column(
        "default_evening_time",
        sa.String(),
        nullable=False,
        server_default="18:00",
    ),
    "default_bedtime": sa.Column(
        "default_bedtime",
        sa.String(),
        nullable=False,
        server_default="22:00",
    ),
}


def upgrade() -> None:
    """기존 사용자 설정을 보존하면서 새 설정 열을 기본값으로 추가한다."""
    inspector = sa.inspect(op.get_bind())
    if "user_settings" not in inspector.get_table_names():
        raise RuntimeError("user_settings table must exist before this migration.")
    existing_columns = {
        str(column["name"])
        for column in inspector.get_columns("user_settings")
    }
    for column_name, column in _SETTING_COLUMNS.items():
        if column_name not in existing_columns:
            op.add_column("user_settings", column)


def downgrade() -> None:
    """새 설정 열만 제거하고 기존 접근성 설정은 유지한다."""
    inspector = sa.inspect(op.get_bind())
    if "user_settings" not in inspector.get_table_names():
        return
    existing_columns = {
        str(column["name"])
        for column in inspector.get_columns("user_settings")
    }
    with op.batch_alter_table("user_settings") as batch_op:
        for column_name in reversed(tuple(_SETTING_COLUMNS)):
            if column_name in existing_columns:
                batch_op.drop_column(column_name)
