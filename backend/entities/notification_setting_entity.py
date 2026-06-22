# File Name: notification_setting_entity.py
# Role: Skeleton entity mapped from the NotificationSetting box in ClassDiagram2.

from pydantic import BaseModel


# Class Name: NotificationSetting
# Role: Represents patient medication notification settings.
class NotificationSetting(BaseModel):
    patient_id: str = ""
    medication_id: str = ""
    alarm_time: str = ""
    enabled: bool = False

    def saveNotificationSetting(self) -> None:
        raise NotImplementedError("Notification settings are not implemented yet.")
