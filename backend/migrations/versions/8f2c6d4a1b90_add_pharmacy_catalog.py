# 파일명: 8f2c6d4a1b90_add_pharmacy_catalog.py
# 역할: 전국 약국 카탈로그 테이블을 추가하고 자동 생성된 로컬 테이블을 안전하게 인수한다.

"""정규화된 전국 약국 카탈로그를 추가한다.

Revision ID: 8f2c6d4a1b90
Revises: 6e1b4a9c2d80
Create Date: 2026-08-24
"""

from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "8f2c6d4a1b90"
down_revision: str | None = "6e1b4a9c2d80"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_PHARMACY_CATALOG_COLUMNS = {
    "pharmacy_id",
    "name",
    "address",
    "telephone",
    "latitude",
    "longitude",
    "weekly_hours",
    "source_updated_at",
}

_PHARMACY_CATALOG_INDEXES = {
    "ix_pharmacy_catalog_records_name": ["name"],
    "ix_pharmacy_catalog_records_latitude": ["latitude"],
    "ix_pharmacy_catalog_records_longitude": ["longitude"],
}


def upgrade() -> None:
    """테이블을 만들거나 호환되는 자동 생성 테이블을 마이그레이션에 편입한다."""
    inspector = sa.inspect(op.get_bind())
    table_exists = "pharmacy_catalog_records" in inspector.get_table_names()
    if not table_exists:
        op.create_table(
            "pharmacy_catalog_records",
            sa.Column("pharmacy_id", sa.String(length=32), nullable=False),
            sa.Column("name", sa.String(length=300), nullable=False),
            sa.Column("address", sa.Text(), nullable=False),
            sa.Column("telephone", sa.String(length=80), nullable=False),
            sa.Column("latitude", sa.Float(), nullable=False),
            sa.Column("longitude", sa.Float(), nullable=False),
            sa.Column("weekly_hours", sa.JSON(), nullable=False),
            sa.Column(
                "source_updated_at",
                sa.DateTime(),
                server_default=sa.text("CURRENT_TIMESTAMP"),
                nullable=False,
            ),
            sa.PrimaryKeyConstraint("pharmacy_id"),
        )
        existing_indexes: set[str] = set()
    else:
        _validate_existing_pharmacy_catalog_table(inspector)
        existing_indexes = {
            str(index["name"])
            for index in inspector.get_indexes("pharmacy_catalog_records")
            if index.get("name")
        }

    for index_name, column_names in _PHARMACY_CATALOG_INDEXES.items():
        if index_name not in existing_indexes:
            op.create_index(
                index_name,
                "pharmacy_catalog_records",
                column_names,
                unique=False,
            )


def downgrade() -> None:
    op.drop_index(
        "ix_pharmacy_catalog_records_longitude",
        table_name="pharmacy_catalog_records",
    )
    op.drop_index(
        "ix_pharmacy_catalog_records_latitude",
        table_name="pharmacy_catalog_records",
    )
    op.drop_index(
        "ix_pharmacy_catalog_records_name",
        table_name="pharmacy_catalog_records",
    )
    op.drop_table("pharmacy_catalog_records")


def _validate_existing_pharmacy_catalog_table(inspector: sa.Inspector) -> None:
    """자동 생성된 약국 테이블이 마이그레이션 스키마와 호환되는지 확인한다."""
    column_names = {
        str(column["name"])
        for column in inspector.get_columns("pharmacy_catalog_records")
    }
    missing_columns = _PHARMACY_CATALOG_COLUMNS - column_names
    if missing_columns:
        missing = ", ".join(sorted(missing_columns))
        raise RuntimeError(
            "Existing pharmacy_catalog_records table is incompatible; "
            f"missing: {missing}"
        )
