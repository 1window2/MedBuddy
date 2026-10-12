"""이미 적용된 카탈로그 갱신과 자원 ID 보호 이력을 합친다."""

revision = "f2c8a6d4e901"
down_revision = ("c5e1a7f3b902", "d19e7c4b2a60")
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 양쪽 부모가 스키마를 완성하므로 이미 적용된 변경은 다시 실행하지 않는다.
    pass


def downgrade() -> None:
    pass
