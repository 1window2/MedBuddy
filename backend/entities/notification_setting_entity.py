# 파일명: notification_setting_entity.py
# 역할: ClassDiagram2의 NotificationSetting에 대응하는 미구현 엔티티이다.

from pydantic import BaseModel


# 클래스명: NotificationSetting
# 역할: 환자 복약 알림 설정을 표현한다.
class NotificationSetting(BaseModel):
    patient_id: str = ""
    medication_id: str = ""
    alarm_time: str = ""
    enabled: bool = False

    def saveNotificationSetting(self) -> None:
        raise NotImplementedError("Notification settings are not implemented yet.")
