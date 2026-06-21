# 파일명: caregiver_notification_entity.py
# 역할: ClassDiagram2의 CaregiverNotification에 대응하는 미구현 엔티티이다.

from pydantic import BaseModel


# 클래스명: CaregiverNotification
# 역할: 보호자 알림 설정을 표현한다.
class CaregiverNotification(BaseModel):
    caregiver_id: str = ""
    patient_id: str = ""
    enabled: bool = False

    def saveCaregiverNotification(self) -> None:
        raise NotImplementedError("Caregiver notification is not implemented yet.")
