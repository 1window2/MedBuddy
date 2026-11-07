# 파일명: d19e7c4b2a60_preserve_deleted_resource_ids.py
# 역할: SQLite 자원 ID 재사용을 막고 푸시 등록 세대를 저장한다.
"""삭제한 약·채팅의 SQLite ID와 푸시 재등록 세대를 보호한다."""

from alembic import op
import sqlalchemy as sa

revision = "d19e7c4b2a60"
down_revision = "b3a7d9e2f601"
branch_labels = None
depends_on = None

_TABLES = ("saved_medications", "chat_messages")

# 기존 SQLite에는 이미 삭제한 최고 ID의 이력이 없다. 이 변경의 재사용 방지는
# 적용 이후에만 보장된다. 적용 전 앱 대기 작업의 동기화를 완료하고 실패·보류
# 항목을 확인한 뒤 작업자를 종료한다. 대상이 불명확한 과거 요청은 자동 재전송하거나
# 조용히 삭제하지 않고 사용자 확인을 거친다. 현재 MAX(id)만으로 이미 삭제된
# 과거 최고 발급 ID를 복구할 수는 없다.


# 함수이름: _rebuild
# 함수역할: SQLite 대상 테이블의 AUTOINCREMENT 설정이 다를 때만 재생성하고 전후 외래키 무결성을 확인한다.
# 매개변수: autoincrement (bool)는 적용할 ID 발급 정책이다.
# 반환값: None. 다른 DB는 변경하지 않으며 위험한 외래키 활성 연결·무결성 실패는 RuntimeError로 거절한다.
def _rebuild(*, autoincrement: bool) -> None:
    connection = op.get_bind()
    if connection.dialect.name != "sqlite":
        return
    targets = []
    for name in _TABLES:
        definition = connection.execute(sa.text(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name=:name"
        ), {"name": name}).scalar_one()
        if ("AUTOINCREMENT" in definition.upper()) != autoincrement:
            targets.append(name)
    if not targets:
        return
    # 외래키가 켜진 기존 연결의 테이블 교체는 자식 행을 삭제하므로 쓰기 전에 거부한다.
    # 빈 DB 초기화는 허용하며, 기존 DB는 앱을 멈추고 전용 Alembic 연결로 갱신한다.
    if connection.exec_driver_sql("PRAGMA foreign_keys").scalar():
        if any(connection.exec_driver_sql(f'SELECT 1 FROM "{name}" LIMIT 1').first()
               for name in targets):
            raise RuntimeError(
                "SQLite ID migration requires a dedicated connection with foreign_keys=OFF. "
                "Stop the backend, back up the database, and run alembic upgrade head."
            )
    if connection.exec_driver_sql("PRAGMA foreign_key_check").first():
        raise RuntimeError("SQLite foreign keys are invalid before ID migration.")
    for name in targets:
        with op.batch_alter_table(
            name, recreate="always", table_kwargs={"sqlite_autoincrement": autoincrement},
        ):
            pass
    if connection.exec_driver_sql("PRAGMA foreign_key_check").first():
        raise RuntimeError("SQLite foreign keys are invalid after ID migration.")


# 함수이름: upgrade
# 함수역할: 약·채팅 ID 재사용을 막고 누락된 푸시 등록 버전 열을 빈 기본값으로 추가한다.
# 매개변수: 없음. Alembic 연결을 사용한다.
# 반환값: None. 재생성 안전성 검증과 DDL 오류는 전달한다.
def upgrade() -> None:
    _rebuild(autoincrement=True)
    columns = {column["name"] for column in sa.inspect(op.get_bind()).get_columns("device_push_tokens")}
    if "registration_version" not in columns:
        # 기존 토큰은 그대로 유지하며 다음 등록부터 독립된 세대 값을 받는다.
        op.add_column("device_push_tokens", sa.Column(
            "registration_version", sa.String(32), nullable=False, server_default="",
        ))


# 함수이름: downgrade
# 함수역할: SQLite AUTOINCREMENT 정책을 해제하고 존재하는 푸시 등록 버전 열을 제거한다.
# 매개변수: 없음. Alembic 연결을 사용한다.
# 반환값: None. ID 재사용 방지·등록 세대 정보가 사라지며 재생성 오류는 전달한다.
def downgrade() -> None:
    _rebuild(autoincrement=False)
    columns = {column["name"] for column in sa.inspect(op.get_bind()).get_columns("device_push_tokens")}
    if "registration_version" in columns:
        op.drop_column("device_push_tokens", "registration_version")
