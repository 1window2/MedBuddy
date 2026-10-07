# 파일명: a6e2d903bc71_add_dose_sync_operations.py
# 역할: 오프라인 복용 요청의 중복 처리를 막는 영수증 테이블을 추가한다.
from alembic import op
import sqlalchemy as sa

revision = "a6e2d903bc71"
down_revision = "7c3d9e1f5a20"
branch_labels = None
depends_on = None


# 함수이름: upgrade
# 함수역할: 테이블을 생성하거나 데모 초기화로 이미 생성된 스키마를 확인한다.
# 매개변수: 없음. 반환값: 없음. 기존 컬럼 구성이 다르면 중단한다.
def upgrade() -> None:
    # 데모 실행은 Alembic 적용 전에 ORM 메타데이터로 테이블을 만들 수 있다.
    inspector = sa.inspect(op.get_bind())
    if inspector.has_table("dose_sync_operations"):
        columns = {column["name"] for column in inspector.get_columns("dose_sync_operations")}
        if columns != {"patient_hash", "operation_id", "payload", "created_at"}:
            raise RuntimeError("Existing dose sync schema does not match this migration.")
        return
    op.create_table(
        "dose_sync_operations",
        sa.Column("patient_hash", sa.String(), sa.ForeignKey("user_accounts.user_hash", ondelete="CASCADE"), primary_key=True),
        sa.Column("operation_id", sa.String(64), primary_key=True),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )


# 함수이름: downgrade
# 함수역할: 이 버전에서 추가한 처리 영수증 테이블을 제거한다.
# 매개변수: 없음. 반환값: 없음.
def downgrade() -> None:
    op.drop_table("dose_sync_operations")
