# 파일명: user_setting_entity.py
# 역할: ClassDiagram2의 UserSetting에 대응하는 미구현 엔티티이다.

from pydantic import BaseModel


# 클래스명: UserSetting
# 역할: 로컬 사용자 표시/읽기 설정을 표현한다.
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
