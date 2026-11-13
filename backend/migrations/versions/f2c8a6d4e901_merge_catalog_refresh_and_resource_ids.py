# 파일명: f2c8a6d4e901_merge_catalog_refresh_and_resource_ids.py
# 역할: 카탈로그 갱신과 자원 ID 보호의 두 마이그레이션 계보를 병합한다.
"""이미 적용된 카탈로그 갱신과 자원 ID 보호 이력을 합친다."""

revision = "f2c8a6d4e901"
down_revision = ("c5e1a7f3b902", "d19e7c4b2a60")
branch_labels = None
depends_on = None


# 함수이름: upgrade
# 함수역할: 부모 리비전이 수행한 변경을 반복하지 않는 병합 지점이다.
# 매개변수: 없음.
# 반환값: None. 별도 DDL이나 데이터 변경은 없다.
def upgrade() -> None:
    # 양쪽 부모가 스키마를 완성하므로 이미 적용된 변경은 다시 실행하지 않는다.
    pass


# 함수이름: downgrade
# 함수역할: 병합 지점 자체에는 되돌릴 스키마 변경이 없어 아무 작업도 하지 않는다.
# 매개변수: 없음.
# 반환값: None. 부모 리비전의 역변경은 Alembic이 별도로 처리한다.
def downgrade() -> None:
    pass
