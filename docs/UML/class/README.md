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
  - 환자·보호자 연동, 조건부 채팅 탭과 대화 목록, 복약 완료 알림 전달 구조를 보여준다.
- `05_AuthenticationSettingsAccessibility.puml` / `05_AuthenticationSettingsAccessibility.png`
  - 인증, 사용자 설정 저장, 언어 및 음성 안내 구조를 보여준다.

## Usage

홈은 약 등록·식별, 복약 알림 설정, 건강 관리 추천, 근처 운영 약국을 2×2로 표시한다.
약 등록·식별에서 처방전 분석, 단일·다중 알약 식별, 직접 입력으로 진입한다.
채팅도 기본 기능이며, 활성 연동이 하나 이상일 때만 하단 채팅 탭을 표시한다.
다중 알약 식별도 기본 기능으로 제공하므로 실험실 메뉴와 전용 설정을 제거한다.
구형 실험실 저장값은 기능을 제한하지 않으며 기존 접근성·알림 설정은 유지한다.
`ManageChatList`는 계정별 활성 연동·별칭·최근 메시지를 조회하고, `ChatListUI`는
여러 상대 중 선택한 연동을 기존 `LinkedChatUI`로 연결한다. 백엔드의 참여자 권한
검증과 메시지·복약 데이터 계약은 변경하지 않는다.

발표에서는 `00`부터 필요한 기능 다이어그램까지 순서대로 사용하고,
전체 `ClassDiagram`은 상세 설명이나 부록에 배치한다. 구조가 변경되면 `.puml`을
먼저 수정한 뒤 같은 이름의 `.png`도 다시 생성한다.
