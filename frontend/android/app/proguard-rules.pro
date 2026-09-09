# 파일명: proguard-rules.pro
# 역할: Android 릴리스 최적화 과정에서 사용하지 않는 OCR 언어 모델의 경고를 제외한다.

# OCR 플러그인이 참조하지만 MedBuddy에서 선택하지 않는 언어 모델은 릴리스 검사에서 제외한다.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
