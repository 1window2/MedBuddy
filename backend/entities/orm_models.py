# File Name: orm_models.py
# Role: Imports every ORM entity module so its tables are registered on the shared metadata.

# The application and Alembic both import this module, so they always see the same set of tables.
from entities import caregiver_alert_outbox_entity  # noqa: F401
from entities import caregiver_notification_entity  # noqa: F401
from entities import catalog_refresh_state_entity  # noqa: F401
from entities import chat_message_entity  # noqa: F401
from entities import chat_notification_job_entity  # noqa: F401
from entities import device_push_token_entity  # noqa: F401
from entities import health_recommendation_cache_entity  # noqa: F401
from entities import medication_alarm_entity  # noqa: F401
from entities import medication_completion_entity  # noqa: F401
from entities import medication_care_entity  # noqa: F401
from entities import dose_sync_operation_entity  # noqa: F401
from entities import medication_detail_entity  # noqa: F401
from entities import patient_caregiver_link_entity  # noqa: F401
from entities import pill_identification_entity  # noqa: F401
from entities import pharmacy_catalog_entity  # noqa: F401
from entities import saved_medication_entity  # noqa: F401
from entities import user_setting_entity  # noqa: F401
from entities import user_account_entity  # noqa: F401
