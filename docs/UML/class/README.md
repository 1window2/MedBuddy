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
  - 환자·보호자 연동, 조건부 채팅 탭과 대화 목록, 알림 전달과 계정별 로컬 알림함 구조를 보여준다.
  - 서버의 미복약 감지와 완료·미복약 Outbox 처리, 완료 채팅 기록 생성을 구분한다.
- `05_AuthenticationSettingsAccessibility.puml` / `05_AuthenticationSettingsAccessibility.png`
  - 인증, 사용자 설정 저장, 언어 및 음성 안내 구조를 보여준다.
  - Firebase 인증과 App Check 적용 조건, 전경 Session 복구를 구분한다.
- `06_DoseSyncAndWidget.puml` / `06_DoseSyncAndWidget.png`
  - 암호화된 복약 전송 큐와 서버 처리 영수증, 홈 위젯의 연결 구조를 보여준다.
  - 본인 복용 기록과 연결 환자의 읽기 전용 조회를 분리한다.
  - `DoseWidgetLayout`은 런처가 배정한 높이와 글자 배율에 맞춰 표시 밀도를 조절하며 기록·조회 경로는 변경하지 않는다.
- `07_NearbyCare.puml` / `07_NearbyCare.png`
  - 공통 병원·약국 지도 UI와 별도 병원 조회·공휴일 확인, 서버가 검증한 채팅 공유 문맥을 보여준다.

## Usage

홈은 약 등록·식별, 건강 관리 추천 / 근처 운영 병원·약국, 환경설정을 2×2로 표시한다.
병원·약국 선택창에서 탐색 대상을 고르고 병원은 진료과목과 조회 조건을 분리한다.
날짜는 조회 조건 창 안에 두며 병원 상세의 공유 버튼은 전화·길찾기 아래에 이어진다.
약국은 지도 이동 후 해당 지역을 검색할 수 있고, 필터·새로고침도 선택한 검색 위치를 유지한다.
마커 또는 목록의 약국을 선택하면 같은 지도에서 접고 펼칠 수 있는 하단 정보창을 연다.
정보창은 내용 높이에 맞춰 지도를 덜 가리고, 큰 글씨나 긴 내용은 스크롤로 확인한다.
선택 전에도 마커 아래에 이름을 표시하며, 밀집 지역의 겹치는 이름은 확대하면 더 보이도록 조정한다.
정보창의 전화·길찾기·즐겨찾기와 채팅 공유를 유지하며, 닫아도 탐색 중인 지도 위치는 바뀌지 않는다.
위치 조회 실패 시 홍익대학교 서울캠퍼스 기준으로 안내하며, 검색 결과가 없어도 지도를 유지한다.
상단 종 버튼은 미확인 개수와 알림함 진입을 제공한다. 복약 알림 설정은 환경설정과 일정에서 유지한다.
알림함은 기기에 보관된 계정별 알림을 종류 구분 없이 최신순으로 표시하며 읽음·삭제 시 원래 대화와 복약 기록은 변경하지 않는다.
채팅은 표시가 허용된 수신 내용의 미리보기를 사용한다. 저장 범위와 예약 기록의 제한은 [알림함 설계 문서](../../MedBuddy%20-%20Notification%20Inbox.md)를 따른다.
약 등록·식별에서 처방전 분석, 단일·다중 알약 식별, 직접 입력으로 진입한다.
건강 관리 추천에서 서버가 복용 약 없음으로 응답하면 같은 약 등록·식별 메뉴를 바로 제공한다.
직접 등록·알약 식별에서 돌아오면 추천을 갱신하며, 처방전 입력은 홈의 기존 OCR 흐름으로 연결한다.
통신·권한·서버 오류는 빈 복용 약 상태와 구분해 재시도를 안내한다.
복약함은 기본 조건을 복용 중으로 두고 하나의 조회 조건 버튼에서 복용 중·복용 종료·전체를 선택한다. 날짜 정렬과 선택 삭제는 유지한다.
채팅도 기본 기능이며, 활성 연동이 하나 이상일 때만 하단 채팅 탭을 표시한다.
다중 알약 식별도 기본 기능으로 제공하므로 실험실 메뉴와 전용 설정을 제거한다.
구형 실험실 저장값은 기능을 제한하지 않으며 기존 접근성·알림 설정은 유지한다.
`ManageChatList`는 계정별 활성 연동·별칭·최근 메시지·미확인 개수를 조회하고, `ChatListUI`는
여러 상대 중 선택한 연동을 기존 `LinkedChatUI`로 연결한다. 백엔드의 참여자 권한
검증과 메시지·복약 데이터 계약은 변경하지 않는다.
알림 진입은 `LinkedChatEntryUI`에서 역할을 확인한다. 최신 위치·고정 읽음 경계와
상대가 읽으면 사라지는 `1` 표시는 [읽음 상태 문서](../../Chat%20Read%20State%20and%20Notification%20Entry.md)를 따른다.

일반 채팅은 복용 약이 없어도 가능하며, HTTP 저장 후 Router에서 WebSocket으로 방송한다.
일반 채팅 Push는 사용자 메시지와 함께 저장한 별도 `chat_notification_jobs`를
`ChatNotificationWorker`가 처리·재시도한다. 전체 Sequence와 Class에도 이 구조를 반영한다.
세부 정책은 [영속 채팅 전달 설계](../../MedBuddy%20-%20Durable%20Chat%20Delivery.md)를 따른다.
Outbox의 자동 완료 메시지 저장 자체는 WebSocket 방송을 수행하지 않는다.
환자의 `먹었어요`는 선택한 약·시간대·날짜를 기기에 먼저 저장하고 서버의 복약
기록과 채팅 영수증을 함께 갱신한다. 응답 전까지 전송 대기를 표시하며 같은 요청을
재전송해도 중복 기록하지 않는다. 일반 채팅 문구로 복용 여부를 추정하지 않는다.
앱 홈과 위젯은 `홈 복약 일정` 설정을 공유한다. 환자가 여러 명이면 앱과 위젯 모두
별칭 옆 화살표로 환자를 전환하며 보호자가 복용 상태를 변경할 수 없다.
앱의 `HomeMedicationSlotPager`는 공통 미리보기 안에서 시간대별 요약만 좌우로 넘긴다.
등록된 약이 있는 시간대만 표시하며, 복용 완료한 시간대도 확인·취소를 위해 유지한다.
시간대가 둘 이상이면 요약 안에 해당 개수만큼 점을 표시하고, 슬라이드와 기록 후 다음 일정 이동에 맞춰 현재 위치를 강조한다.
본인 화면의 완료·취소는 기존 ViewModel 기록 경로로 전달하고, 보호자는 상세 조회만 제공한다.
채팅 기록·약국 자료·Pill Catalog는 Application Database를 사용하며,
알림함과 직접 등록 사진은 기기에 저장한다. Redis Counter와 프로세스 메모리의
WebSocket 연결 Registry를 채팅 Database 또는 분산 방송 broker로 혼동하지 않는다.

홈·채팅·일정·위젯의 조회 재사용 범위, 실패 복구와 사진 처리 분리는
[클라이언트 조회·갱신 정책](../../MedBuddy%20-%20Client%20Refresh%20Policy.md)을 따른다.
보호자 홈은 모든 활성 환자의 오늘 일정을 일괄 조회하며 약 상세는 포함하지 않는다.
정상 채팅 연결에서는 반복 조회를 멈추고 복귀·장애 시 누락분을 확인한다.

`MedBuddyViewModel`은 기존 화면 API를 유지하면서 처방·저장 약·일정·알림·설정·건강 추천의
독립 ViewModel에 상태 관리를 위임한다. 홈의 '연결된 환자 일정 보기'는 화면 및 음성 설정으로
이동할 뿐 선택값을 자동 변경하지 않는다. 알림을 모두 끈 연결 환자도 홈·위젯에서 조회한다.
미복약 판단은 모든 인증 mode에서 서버가 담당하며, 개발 mode의 기기는 처리 완료된 요청을 조회한다.
'10분 후 다시 알림'은 전달 건별 child Outbox, '채팅으로 알림'은 원본 건별 기존 채팅 요청을 재사용한다.
두 action 모두 서버에서 현재 권한과 유효성을 확인하며 환자의 복약 기록을 변경하지 않는다.

발표에서는 `00`부터 필요한 기능 다이어그램까지 순서대로 사용하고,
전체 `ClassDiagram`은 상세 설명이나 부록에 배치한다. 구조가 변경되면 `.puml`을
먼저 수정한 뒤 같은 이름의 `.png`도 다시 생성한다.

기존 beta/v0.2.0 정합성 갱신은 텍스트 원본만 반영했다. 2026-09-21에는 새 `06`
클래스 그림과 복약 동기화·홈 위젯·전체 시스템 시퀀스 PNG를 원본에서 생성했다.
그 밖의 기존 PNG는 최신 텍스트 원본과 차이가 있을 수 있다.

2026-09-29 갱신은 `63b6165`의 실제 구현과 각 문서의 최근 수정 내용을 대조했다.
이번에는 `.md`·`.puml`만 갱신하고 PNG는 생성·변경하지 않았으므로 최신 내용은 텍스트 원본을 기준으로 확인한다.

2026-10-02에는 원문 함량·제형 검증, 약명 후보 직접 확인과 계정 잠금 재시도,
위젯 완료 후 날짜별 재알림 취소를 자연어 명세와 UML에 반영했다.
`02_PrescriptionAnalysis`, `06_DoseSyncAndWidget`, `ClassDiagram`,
`HomeDoseWidget`, `OverallSystemSequenceDiagram`의 PNG도 해당 원본에서 다시 생성했다.
상세 계약은 [약명 매칭과 후보 확인](../../Medication%20Matching%20Review.md),
검증 범위는 [2026-10-02 기록](../../qa/v0.2.0-2026-10-02-medication-matching-widget.md)을 참고한다.

The 2026-10-03 refactoring update preserves those medication-review and widget
flows. Prescription verification, notification protocol ownership, account-lock
cleanup and cancellation-safe request database work are reflected in the changed
sources and their regenerated PNGs. `ClassDiagram` explicitly uses the bundled
ELK layout engine; the compact feature diagrams retain Smetana. Rendered locally
with PlantUML 1.2026.6 without transmitting diagram source to a remote service.

The follow-up refactoring separates medication-detail cache, summary, name matching
and local catalog collaborators; nearby hospital/pharmacy controls are siblings
under `CheckNearbyCare`, and generic GPS values live outside the pharmacy module.
Chat history/recovery/read state belongs to `LinkedChatHistoryViewModel`, while
conversation-scoped presentation retains composer, navigation and adapter ownership.
The changed class and sequence PNGs are regenerated together with their sources.

The 2026-10-05 continuation gives outgoing chat requests a separate
`LinkedChatComposerViewModel` and immutable `ChatMessageDraft`; screen text fields
and navigation remain presentation-owned. Shared nearby-care display/search and
selection values use neutral entities with explicit radii, while provider wire
fields and favorite-storage namespaces remain unchanged. Prescription verification
captures an Engine-bound worker factory before async work; Connection-bound request
transactions are never passed to catalog workers. The seven affected class/sequence
sources and matching PNGs are synchronized locally.
