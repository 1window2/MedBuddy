# 파일명: env.py
# 역할: Alembic 마이그레이션 실행 환경과 데이터베이스 연결을 구성한다.

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from core.config import settings
from core.database import Base
from entities import caregiver_notification_entity  # noqa: F401
from entities import chat_message_entity  # noqa: F401
from entities import device_push_token_entity  # noqa: F401
from entities import health_recommendation_cache_entity  # noqa: F401
from entities import medication_alarm_entity  # noqa: F401
from entities import medication_completion_entity  # noqa: F401
from entities import medication_detail_entity  # noqa: F401
from entities import patient_caregiver_link_entity  # noqa: F401
from entities import pill_identification_entity  # noqa: F401
from entities import pharmacy_catalog_entity  # noqa: F401
from entities import saved_medication_entity  # noqa: F401
from entities import user_setting_entity  # noqa: F401
from entities import user_account_entity  # noqa: F401

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name, disable_existing_loggers=False)

database_url = config.attributes.get("database_url", settings.DATABASE_URL)
config.set_main_option("sqlalchemy.url", str(database_url).replace("%", "%%"))
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=str(database_url),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
