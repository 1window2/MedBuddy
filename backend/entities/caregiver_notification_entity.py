# File Name: caregiver_notification_entity.py
# Role: Skeleton entity mapped from the CaregiverNotification box in ClassDiagram2.

from pydantic import BaseModel


# Class Name: CaregiverNotification
# Role: Represents caregiver notification settings.
class CaregiverNotification(BaseModel):
    caregiver_id: str = ""
    patient_id: str = ""
    enabled: bool = False

    def saveCaregiverNotification(self) -> None:
        raise NotImplementedError("Caregiver notification is not implemented yet.")
