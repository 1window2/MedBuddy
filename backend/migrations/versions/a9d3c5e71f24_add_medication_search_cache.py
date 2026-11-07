# 파일명: a9d3c5e71f24_add_medication_search_cache.py
# 역할: 채팅에 첨부하는 검색약을 서버 값으로 다시 만들기 위한 공개 품목 정보 임시 저장소를 추가한다.

from alembic import op
import sqlalchemy as sa

revision = "a9d3c5e71f24"
down_revision = "f7a2c9e4b610"
branch_labels = None
depends_on = None


# 함수이름: upgrade
# 함수역할: 검색한 계정 정보 없이 품목번호별 공개 표시 정보와 조회 시각을 보관하는 표를 만든다.
# 매개변수: 없음. 반환값: 없음.
def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    if not inspector.has_table("medication_search_cache"):
        op.create_table(
            "medication_search_cache",
            sa.Column("item_seq", sa.String(length=64), primary_key=True),
            sa.Column("item_name", sa.String(length=300), nullable=False),
            sa.Column("manufacturer", sa.String(length=200), nullable=False, server_default=""),
            sa.Column("image_url", sa.String(length=2048), nullable=False, server_default=""),
            sa.Column("fetched_at", sa.DateTime(), nullable=False),
        )
    # 로컬 create_all로 이미 만든 표도 데이터를 보존한 채 받아들인다.
    indexes = {item["name"] for item in sa.inspect(op.get_bind()).get_indexes("medication_search_cache")}
    if "ix_medication_search_cache_fetched_at" not in indexes:
        op.create_index("ix_medication_search_cache_fetched_at", "medication_search_cache", ["fetched_at"])


# 함수이름: downgrade
# 함수역할: 임시 검색 캐시만 지우고 대화·저장 약·복용 기록은 유지한다.
# 매개변수: 없음. 반환값: 없음.
def downgrade() -> None:
    op.drop_index("ix_medication_search_cache_fetched_at", table_name="medication_search_cache")
    op.drop_table("medication_search_cache")
