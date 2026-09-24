# 파일명: 6d4f8a2c9301_add_pharmacy_search_cache.py
# 역할: 공공 보완 검색에서 찾은 약국의 채팅 공유용 임시 저장소를 추가한다.

from alembic import op
import sqlalchemy as sa

revision = "6d4f8a2c9301"
down_revision = "f8a2c6d901be"
branch_labels = None
depends_on = None


# 함수이름: upgrade
# 함수역할: 전국 카탈로그와 별개로 공개 약국 정보 및 캐시 시각을 보관한다.
# 매개변수: 없음. 반환값: 없음.
def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    if not inspector.has_table("pharmacy_search_cache"):
        op.create_table(
            "pharmacy_search_cache",
            sa.Column("pharmacy_id", sa.String(length=32), primary_key=True),
            sa.Column("name", sa.String(length=300), nullable=False),
            sa.Column("address", sa.Text(), nullable=False),
            sa.Column("telephone", sa.String(length=80), nullable=False),
            sa.Column("latitude", sa.Float(), nullable=False),
            sa.Column("longitude", sa.Float(), nullable=False),
            sa.Column("fetched_at", sa.DateTime(), nullable=False),
        )
    # 과거 로컬 create_all로 이미 생성된 테이블도 데이터 보존 상태로 수용한다.
    indexes = {item["name"] for item in sa.inspect(op.get_bind()).get_indexes("pharmacy_search_cache")}
    if "ix_pharmacy_search_cache_fetched_at" not in indexes:
        op.create_index("ix_pharmacy_search_cache_fetched_at", "pharmacy_search_cache", ["fetched_at"])


# 함수이름: downgrade
# 함수역할: 임시 검색 캐시만 제거하고 카탈로그·대화·복용 기록은 유지한다.
# 매개변수: 없음. 반환값: 없음.
def downgrade() -> None:
    op.drop_index("ix_pharmacy_search_cache_fetched_at", table_name="pharmacy_search_cache")
    op.drop_table("pharmacy_search_cache")
