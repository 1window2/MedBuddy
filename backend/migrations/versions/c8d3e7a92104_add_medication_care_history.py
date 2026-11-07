# 파일명: c8d3e7a92104_add_medication_care_history.py
# 역할: 기존 복약 기록을 보존하며 약 버전·필요시 복용·정정 이력을 추가한다.

from alembic import op
import sqlalchemy as sa

revision = "c8d3e7a92104"
down_revision = "ab29d71c4e60"
branch_labels = None
depends_on = None


# 함수이름: upgrade
# 함수역할: 저장 약품에 복약 버전·중단 정보를, 완료 기록에 보고·수정 정보를 추가하고 중복 작업 영수증 및 변경 감사 테이블과 인덱스를 생성한다.
# 매개변수: 없음. Alembic의 현재 연결을 사용한다.
# 반환값: 없음. 기존 약품은 정기 복용·초기 버전 기본값을 받으며 DDL 실패는 전파한다.
def upgrade() -> None:
    for column in (
        sa.Column("dosing_mode", sa.String(16), nullable=False, server_default="scheduled"),
        sa.Column("regimen_revision", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("regimen_effective_from", sa.Date(), nullable=True),
        sa.Column("stopped_on", sa.Date(), nullable=True),
        sa.Column("superseded_by_id", sa.Integer(), nullable=True),
    ):
        op.add_column("saved_medications", column)
    for column in (
        sa.Column("report_status", sa.String(16), nullable=True),
        sa.Column("actual_taken_at", sa.DateTime(), nullable=True),
        sa.Column("recorded_at", sa.DateTime(), nullable=True),
        sa.Column("reason", sa.String(500), nullable=False, server_default=""),
        sa.Column("revision", sa.Integer(), nullable=False, server_default="0"),
    ):
        op.add_column("medication_completions", column)
    op.create_table(
        "medication_care_operations",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("patient_hash", sa.String(), sa.ForeignKey("user_accounts.user_hash", ondelete="CASCADE"), nullable=False),
        sa.Column("operation_id", sa.String(36), nullable=False),
        sa.Column("request_hash", sa.String(64), nullable=False),
        sa.Column("response_json", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("patient_hash", "operation_id", name="uq_care_operation_owner"),
    )
    op.create_index("ix_medication_care_operations_patient_hash", "medication_care_operations", ["patient_hash"])
    op.create_table(
        "medication_care_audits",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("patient_hash", sa.String(), sa.ForeignKey("user_accounts.user_hash", ondelete="CASCADE"), nullable=False),
        sa.Column("medication_id", sa.Integer(), sa.ForeignKey("saved_medications.id", ondelete="CASCADE"), nullable=False),
        sa.Column("kind", sa.String(32), nullable=False),
        sa.Column("before_json", sa.Text(), nullable=False),
        sa.Column("after_json", sa.Text(), nullable=False),
        sa.Column("recorded_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_medication_care_audits_patient_hash", "medication_care_audits", ["patient_hash"])
    op.create_index("ix_medication_care_audits_medication_id", "medication_care_audits", ["medication_id"])


# 함수이름: downgrade
# 함수역할: 돌봄 감사·작업 영수증 테이블과 복약 버전·완료 보고 열을 제거한다. SQLite 자식 외래키를 보존하도록 직접 열 삭제를 사용한다.
# 매개변수: 없음. Alembic의 현재 연결을 사용한다.
# 반환값: 없음. 추가 이력 데이터는 삭제되며 DDL 실패는 전파한다.
def downgrade() -> None:
    op.drop_table("medication_care_audits")
    op.drop_table("medication_care_operations")
    # SQLite의 테이블 재작성으로 자식 FK가 지워지지 않도록 지원되는 DROP COLUMN을 사용한다.
    for name in ("report_status", "actual_taken_at", "recorded_at", "reason", "revision"):
        op.drop_column("medication_completions", name)
    for name in ("dosing_mode", "regimen_revision", "regimen_effective_from", "stopped_on", "superseded_by_id"):
        op.drop_column("saved_medications", name)
