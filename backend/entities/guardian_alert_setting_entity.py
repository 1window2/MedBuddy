# File Name: guardian_alert_setting_entity.py
# Role: Skeleton entity mapped from the GuardianAlertSetting box in ClassDiagram2.

from pydantic import BaseModel


# Class Name: GuardianAlertSetting
# Role: Represents guardian alert settings.
class GuardianAlertSetting(BaseModel):
    guardian_id: str = ""
    patient_id: str = ""
    enabled: bool = False

    def saveGuardianAlertSetting(self) -> None:
        raise NotImplementedError("Guardian alert setting is not implemented yet.")
