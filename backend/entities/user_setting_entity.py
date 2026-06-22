# File Name: user_setting_entity.py
# Role: Skeleton entity mapped from the UserSetting box in ClassDiagram2.

from pydantic import BaseModel


# Class Name: UserSetting
# Role: Represents local user display and reading settings.
class UserSetting(BaseModel):
    font_size: int = 16
    reading_speed: float = 1.0
    language: str = "ko"

    def getUserSetting(self) -> "UserSetting":
        return self

    def changeFontSize(self, font_size: int) -> "UserSetting":
        return self.model_copy(update={"font_size": font_size})

    def changeReadingSpeed(self, reading_speed: float) -> "UserSetting":
        return self.model_copy(update={"reading_speed": reading_speed})

    def changeLanguage(self, language: str) -> "UserSetting":
        return self.model_copy(update={"language": language})
