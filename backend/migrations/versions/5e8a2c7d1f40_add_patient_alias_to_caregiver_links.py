# 파일명: 5e8a2c7d1f40_add_patient_alias_to_caregiver_links.py
# 역할: 보호자가 지정한 환자 별칭을 연동 관계에 저장한다.

"""환자·보호자 연동 테이블에 환자 별칭 열을 추가한다.

Revision ID: 5e8a2c7d1f40
Revises: d8c2f1a4b690
Create Date: 2026-08-25
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "5e8a2c7d1f40"
down_revision: str | None = "d8c2f1a4b690"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """기존 연동을 유지하면서 선택형 환자 별칭 열을 추가한다."""
    inspector = sa.inspect(op.get_bind())
    if "patient_caregiver_links" not in inspector.get_table_names():
        raise RuntimeError(
            "patient_caregiver_links table must exist before this migration."
        )
    existing_columns = {
        str(column["name"])
        for column in inspector.get_columns("patient_caregiver_links")
    }
    if "patient_alias" not in existing_columns:
        op.add_column(
            "patient_caregiver_links",
            sa.Column("patient_alias", sa.String(length=20), nullable=True),
        )


def downgrade() -> None:
    """환자 별칭 열만 제거하고 연동 관계는 유지한다."""
    inspector = sa.inspect(op.get_bind())
    if "patient_caregiver_links" not in inspector.get_table_names():
        return
    existing_columns = {
        str(column["name"])
        for column in inspector.get_columns("patient_caregiver_links")
    }
    if "patient_alias" in existing_columns:
        with op.batch_alter_table("patient_caregiver_links") as batch_op:
            batch_op.drop_column("patient_alias")
