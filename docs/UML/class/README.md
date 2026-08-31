# Class Diagram Guide

이 폴더에는 전체 클래스 설계와 발표용 단계별 클래스 다이어그램을 함께 관리한다.
같은 이름의 `.puml`은 원본 코드이고 `.png`는 발표 및 문서 확인용 렌더링 이미지다.

## Files

- `ClassDiagram.puml` / `ClassDiagram.png`
  - 전체 클래스, 속성, 관계를 포함한 상세 설계 원본이다.
  - 구현 구조를 확인하거나 발표 부록에서 사용할 때 적합하다.
- `00_SystemOverview.puml` / `00_SystemOverview.png`
  - Frontend, Backend, Database, 외부 서비스의 전체 연결 구조를 간단히 보여준다.
- `01_FeatureMap.puml` / `01_FeatureMap.png`
  - Frontend와 Backend 내부를 주요 기능 영역으로 나눠 보여준다.
- `02_PrescriptionAnalysis.puml` / `02_PrescriptionAnalysis.png`
  - 처방전 촬영, 로컬 OCR, 서버 분석, 사용자 검토 흐름을 보여준다.
- `03_MedicationManagement.puml` / `03_MedicationManagement.png`
  - 약 상세정보, 저장된 복약 정보, 오늘의 복약 일정과 알림 구조를 보여준다.
- `04_CaregiverNotifications.puml` / `04_CaregiverNotifications.png`
  - 환자·보호자 연동과 복약 완료 알림 전달 구조를 보여준다.
- `05_AuthenticationSettingsAccessibility.puml` / `05_AuthenticationSettingsAccessibility.png`
  - 인증, 사용자 설정 저장, 언어 및 음성 안내 구조를 보여준다.

## Usage

발표에서는 `00`부터 필요한 기능 다이어그램까지 순서대로 사용하고,
전체 `ClassDiagram`은 상세 설명이나 부록에 배치한다. 구조가 변경되면 `.puml`을
먼저 수정한 뒤 같은 이름의 `.png`도 다시 생성한다.
