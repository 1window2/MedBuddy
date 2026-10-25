# Class Diagram Guide

이 폴더에는 주요 책임과 계약을 보여주는 전체 구조 및 발표용 단계별 클래스 다이어그램을 함께 관리한다.
같은 이름의 `.puml`은 설계 원본이고 `.png`는 그 렌더링 이미지다.
현재 갱신은 `beta/v0.2.4`의 `77a0f26`까지 통합한 기준과 이후 로컬 기능 찾기를
반영한다. 이전 2026-10-22 원본 12개·대응 PNG 재생성 기록은 아래에 보존한다.
이번 대상과 검증 결과는 별도 절에 구분하며 변경하지 않은 그림은 유지한다.
이 문서와 그림은 개발 브랜치의 설계이며 운영 배포·출시 완료를 뜻하지 않는다.
원본과 그림이 다르면 텍스트 원본을 기준으로 하고 대응 PNG도 함께 갱신한다.

## Files

- `ClassDiagram.puml` / `ClassDiagram.png`
  - 주요 클래스, 속성, 관계를 포함한 상세 설계 원본이며 모든 코드 클래스의 목록은 아니다.
  - 구현 구조를 확인하거나 발표 부록에서 사용할 때 적합하다.
- `00_SystemOverview.puml` / `00_SystemOverview.png`
  - Frontend, Backend, Database, 외부 서비스의 전체 연결 구조를 간단히 보여준다.
- `01_FeatureMap.puml` / `01_FeatureMap.png`
  - Frontend와 Backend 내부를 주요 기능 영역으로 나눠 보여준다.
- `02_PrescriptionAnalysis.puml` / `02_PrescriptionAnalysis.png`
  - 처방전 촬영, 로컬 OCR, 서버 분석, 사용자 검토 흐름을 보여준다.
- `03_MedicationManagement.puml` / `03_MedicationManagement.png`
  - 약 상세정보, 저장된 복약 정보, 오늘 일정과 알림, 적용일별 처방 변경·기록 정정·CSV 공유 구조를 보여준다.
- `04_CaregiverNotifications.puml` / `04_CaregiverNotifications.png`
  - 환자·보호자 연동, 조건부 채팅 탭과 대화 목록, 알림 전달과 계정별 로컬 알림함 구조를 보여준다.
  - 서버의 미복약 감지와 완료·미복약 Outbox 처리, 완료 채팅 기록 생성을 구분한다.
  - 필요시 개별 복용 알림의 명시적 구독·안정된 이벤트 키·읽기 전용 보호자 조회를 정기 시간대 완료와 구분한다.
- `05_AuthenticationSettingsAccessibility.puml` / `05_AuthenticationSettingsAccessibility.png`
  - 인증, 사용자 설정 저장, 언어 및 음성 안내 구조를 보여준다.
  - Firebase 인증과 App Check 적용 조건, 전경 Session 복구를 구분한다.
  - '복약 및 알림'에 통합한 기기 권한·테스트 설정과 설명 전용 데이터 이용 안내를 구분한다.
- `06_DoseSyncAndWidget.puml` / `06_DoseSyncAndWidget.png`
  - 암호화된 복약 전송 큐와 서버 처리 영수증, 홈 위젯의 연결 구조를 보여준다.
  - 본인 복용 기록과 연결 환자의 읽기 전용 조회를 분리한다.
  - `DoseWidgetLayout`은 런처가 배정한 높이와 글자 배율에 맞춰 표시 밀도를 조절하며 기록·조회 경로는 변경하지 않는다.
- `07_NearbyCare.puml` / `07_NearbyCare.png`
  - 공통 병원·약국 지도 UI와 별도 병원 조회·공휴일 확인, 서버가 검증한 채팅 공유 문맥을 보여준다.
- `08_FeatureSearch.puml` / `08_FeatureSearch.png`
  - 로컬 검색 UI·매칭 Control·정적 목적지 Entity와 기존 화면 연결 경계를 보여준다.
  - 27개 목적지의 전체 목록은 [기능 찾기 문서](../../Feature%20Search.md)를 따른다.

## Usage

### v0.2.4 기능 찾기와 현행화

기존 화면·서버 API·DB 구조를 유지하고 탐색 진입점을 보완한다. `FeatureSearchUI`는
화면 메모리의 검색어를 `FindAppFeature`로 평가하고 사용자가 선택한 `AppFeature`만
반환한다. `HomeScreen`은 같은 세션을 확인해 기존 화면으로 연결하며 검색 자체에는
외부 AI·네트워크·계정 자료 조회가 없다. 설정 목적지는 분류·스크롤 위치만 지정한다.
본인 기록과 연결 환자 조회는 구분하고, 공유 목적지는 최초 조회 성공 후 기존 확인창만
연다. 변경·삭제·전송에는 기존 기능의 사용자 확인과 Control 권한 검증을 적용한다.

- `01_FeatureMap`에 프런트엔드 전용 기능 찾기를 추가한다.
- `08_FeatureSearch`와 [FeatureSearch 시퀀스](../sequence/FeatureSearch.puml)를 추가한다.
- 기존 유스케이스 그림·설명에 UC-38을 추가한다. 모든 목적지를 필수 실행하는
  `include` 관계로 표현하지 않으며 상세 이동은 전용 시퀀스에서 구분한다.
- PRN 최초 로딩, 계정 welcome 정렬과 영어 표시 보완은 상태·릴리스 문서에서 다룬다.
  기존 알림 채널 ID, 복용 데이터, 사용자 권한 계약은 바뀌지 않는다.
- 자연어 문서는 월 달력, 암호화 PRN 대기, CSV 최대 90일/채팅 최대 31일,
  통합 기기 알림 설정 등 이미 반영된 최신 베타 내용을 함께 맞춘다.

전체 `ClassDiagram`과 `OverallSystemSequenceDiagram`은 기존 통합 기준선을 유지한다.
이번 탐색의 상세는 새 기능별 그림과 [UC-38 설명](../usecase/UseCaseDescription.md)을
기준으로 한다. 과거 릴리스·실기기 검증 결과를 이번 로컬 변경의 검증으로 간주하지 않는다.

2026-10-25 검증 결과:

- PlantUML 1.2026.8로 전체 원본 19개의 구문 검사를 수행했고 종료 코드는 0이다.
- 이번 대상 `01_FeatureMap`, `08_FeatureSearch`, `FeatureSearch` 시퀀스,
  `UseCaseDiagram`의 PNG 4개를 로컬에서 재생성했다. 원본을 외부 서버로 보내지 않았다.
- PNG 읽기·크기·원본 이후 갱신 시각을 확인하고 이미지를 직접 검사했다.
  새 기능 찾기 그림은 정상 표시되며, 기존 대형 유스케이스의 복잡한 관계선 배치는
  유지한다. 확대가 필요한 전체 그림을 발표용 단일 화면으로 재구성한 작업은 아니다.
- 변경한 자연어 문서 7개의 상대 링크와 코드의 목적지 27개 일치를 확인했다.
  추가 문장에는 로컬 절대경로·이메일·대표적인 키 패턴이 없음을 검사했다.
- 애플리케이션 테스트·실기기 동작·출시 보안 검증은 이 문서 검증에 포함하지 않는다.

재검증 시 기존 안내대로 `JAVA_HOME`, `PLANTUML_JAR`를 준비하고 저장소 루트에서
전체 원본에 `-charset UTF-8 -checkonly -failfast2`를 적용한다. 위 4개 원본의 PNG는
`-DPLANTUML_LIMIT_SIZE=12000`과 `-tpng`으로 생성한다. 아래 12개 목록은 과거
2026-10-22 재생성 기록이며 이번 변경 목록과 구분한다.

### 2026-10-22 개발 브랜치 기준

현재 개발 브랜치의 구현을 반영한 설계이며 출시·배포 완료를 뜻하지 않는다.
기존 유스케이스의 CSV 공유와 채팅 공유 설명은 유지하고 다음 책임 경계를 보완했다.

- **기록 공유:** `ShareMedicationHistory`는 같은 환자의 활성 대화만 선택하고 세션을 확인한다.
  서버 `ManageLinkedChat`은 양쪽 계정 잠금 뒤 삭제 상태·현재 연결을 재검증하고,
  `ManageMedicationCare`가 계산한 기간·상태별 건수를 메시지와 Push 작업에 함께 저장한다.
  같은 요청은 원래 요약을 돌려주며 최신 기록은 현재 권한으로 다시 읽는다. 공유 상세는
  환자에게도 읽기 전용이고 Push에는 건강정보를 포함하지 않는다. 공유 요청 ID는 Control
  생존 범위에만 남으며 기기 영속 큐는 아니다.
- **필요시 대기:** `AsNeededPendingStore`와 `DoseHistoryPendingStore` 확장은 새 필요시
  복용 의도·UUID·확정 시각을 기존 암호화 DB에 보관한다. 같은 계정의 미확정 의도를 먼저
  복원하고 ACK 확인 후 제거한다. 정기 자동 전송 큐 및 기존 기록 정정과는 구분한다.
- **오프라인 일정:** `OfflineScheduleWindow`와 `DoseOfflineScheduleStore` 확장은 서버의
  시작일·종료일을 확인한 최대 14일 안에서만 앱·위젯의 정기 일정을 계산한다. 전날 완료를
  복사하지 않으며 계정·날짜·캐시 revision을 검사한다. 처방 변경·삭제 전후 캐시를 무효화해
  응답 유실에도 이전 처방을 살리지 않으며 변경된 처방 revision은 서버가 거절한다.
- **세션 종료 실패:** 로그아웃 준비 중 실패하면 캡처한 동일 세션·세대에만 저장소·위젯·알림·
  background 작업·Push 복구를 각각 시도한다. 실패한 복구를 성공으로 간주하지 않는다.
- **삭제·원자성:** 약 삭제와 만료 정리는 원본·교체 약 관련 복약 관리 영수증의 건강정보 응답을
  같은 트랜잭션에서 비운다. 요청 ID·서명·표식은 재전송 방지용으로 남기며 동일 요청은 410이다.
  새 약 저장의 만료 정리도 해당 저장 트랜잭션에 포함되어 실패하면 함께 롤백한다.
- **보호자 Push:** 정기 완료는 Outbox ID·생성 시각으로 만든 키를 서버 재시도·OS 표시·알림함에
  재사용한다. 계정별 성공 표시 표식은 재시작 후에도 중복을 줄이지만 정확히 한 번 전달 보장은 아니다.
- **보안 경계:** 처방 텍스트는 서버 제어와 제공자 호출 직전 모두 비식별 검사를 거치며 안전한
  분리가 어려우면 AI 호출 전 거절한다. 운영 요청 제한 Redis는 조회 Cache와 다른 서버를 쓰고
  시작 시 `noeviction`을 확인한다. 모든 개인정보 제거 보증이나 분산 채팅 broker는 아니다.
- **설정:** 독립 `NotificationReadinessUI`는 제거되고 `NotificationDeviceSettings`가
  '복약 및 알림'에 포함된다. `NotificationReadinessControl` 이름은 유지하되 약 등록 점검은 없다.

흐름은 [복약 기록·공유](../sequence/MedicationCareHistory.puml),
[필요시 대기·알림](../sequence/AsNeededCaregiverNotification.puml),
[오프라인 일정·전송](../sequence/OfflineDoseSync.puml),
[전체 시퀀스의 로그아웃 복구](../sequence/OverallSystemSequenceDiagram.puml)와
[자연어 유스케이스](../usecase/UseCaseDescription.md)를 함께 확인한다.
새 다이어그램은 추가하지 않았다. 세부 클래스는 기능별 그림이 기준이며 전체 클래스 그림은
기존 통합 기준선에 보안 경계만 보완한다.

### PNG 재생성·검사

2026-10-22에 다음 12개 원본과 같은 이름의 PNG를 갱신했다. 외부 렌더링 서버에는
원본을 전송하지 않았다. 전체 17개 원본의 구문 검사와 12개 PNG의 읽기·크기·내용 검사를
수행했고, 각 이미지를 열어 빈 화면·오류 이미지·눈에 띄는 겹침을 확인했다.
`00`의 한글 글꼴 누락은 Malgun Gothic으로, `02`의 겹친 관계선 라벨은 간격·배치로 보정했다.
전체 클래스와 전체 시퀀스는 기존 `4096*4096` 축소 기준을 유지하므로 세부 내용은
기능별 그림과 원본을 함께 확인한다. 이 검사는 애플리케이션 테스트나 PostgreSQL CI 통과를 뜻하지 않는다.

같은 그림을 재생성하려면 Java와 PlantUML 1.2026.8을 준비하고 `JAVA_HOME`,
`PLANTUML_JAR`를 각 개발 환경의 경로로 설정한다. 저장소 루트에서 실행한다.

```powershell
$root = Join-Path (Get-Location) 'docs/UML'
$files = @(
  'class/00_SystemOverview.puml',
  'class/02_PrescriptionAnalysis.puml',
  'class/03_MedicationManagement.puml',
  'class/04_CaregiverNotifications.puml',
  'class/05_AuthenticationSettingsAccessibility.puml',
  'class/06_DoseSyncAndWidget.puml',
  'class/ClassDiagram.puml',
  'sequence/AsNeededCaregiverNotification.puml',
  'sequence/MedicationCareHistory.puml',
  'sequence/OfflineDoseSync.puml',
  'sequence/OverallSystemSequenceDiagram.puml',
  'usecase/UseCaseDiagram.puml'
) | ForEach-Object { Join-Path $root $_ }
& (Join-Path $env:JAVA_HOME 'bin/java.exe') `
  '-Djava.awt.headless=true' '-DPLANTUML_LIMIT_SIZE=12000' `
  -jar $env:PLANTUML_JAR `
  -charset UTF-8 -tpng -failfast2 -nberr @files
```

렌더러 종료 코드는 0이며, 생성 PNG 12개는 대응 원본보다 새 파일임을 확인했다.

### 기존 설계 기준선

기존 v0.2.2의 취소·Session 격리, 설정·알림 저장 직렬화, 미전송 복용 기록 반영,
연결 해제 확인, 비매일 일정, SQLite ID 보존과 Push 등록 버전 검증을 유지한다.
추가로 직접 등록·낱알 일정 검토의 복용 주기 선택, 복약함의 다음 복용일,
계정별 저장 약·활성 연결 한도와 채팅 연결 거절·연동 해제 처리를 반영했다.
`LinkedChatDoseRecorder`가 선택 복약 기록을 맡고, 설정 저장은 독립 설정
ViewModel에 위임한다. 보조 그림도 이 책임과 전체 Sequence에 맞춘다.
모든 DTO·helper를 나열하지 않으며 module-level 함수와 Dart extension을
독립 클래스처럼 표현하지 않는다. 이번에 변경한 원본과 PNG는 위 재생성 목록대로 동기화했다.

2026-10-17의 `beta/v0.2.3` 복약 관리 확장은 기능별 `03`, `04`, `05`와
[유스케이스](../usecase/UseCaseDiagram.puml),
[복약 기록 시퀀스](../sequence/MedicationCareHistory.puml),
[필요시 보호자 알림 시퀀스](../sequence/AsNeededCaregiverNotification.puml)에 반영한다.
이 갱신은 책임·권한·저장·전달 경계만 다루며 전체 구조 그림을 UI 문구나 간격마다
재작성하지 않는다. 이전 전체 그림은 통합 기준선이며 새 계약의 상세는 위 기능별 그림과
[복약 관리·기록 문서](../../Medication%20Care%20and%20History.md)를 따른다.
큰 그림의 글자와 하단을 보존하려면 로컬 PlantUML 실행 시 JVM 옵션
`-DPLANTUML_LIMIT_SIZE=12000`과 `-charset UTF-8`을 사용한다.
기능별 클래스 PNG는 각 원본에 지정된 배치·축소 크기를 따른다.

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
복약함은 기본 조건을 전체로 두고 하나의 조회 조건 버튼에서 복용 중·복용 종료·전체를 선택한다. 중단·교체된 약과 과거 기록은 남기며 날짜 정렬과 별도의 선택 삭제는 유지한다.
매일 복용하지 않는 약은 주기와 다음 복용일을 안내한다. 직접 등록·낱알 일정 검토의
매일·격일·주 1회·월 1회 선택은 복용일의 횟수·시간대와 구분한다. 월간은 현재 30일
주기이며 쉬는 날에도 복용 과정과 알림 설정은 유지한다. 새 약이나 연결이 계정 한도를
넘으면 정리 후 재시도를 안내하고 기존 중복 저장·활성 연결은 추가 생성하지 않는다.
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
현재 Client는 `chat-close-codes`를 선언해 거절된 WebSocket의 인증·한도·연결 오류를
구분한다. 구형 Client는 승인 전 거절을 유지한다. 이력 조회에서 연결 해제·권한 상실을
확인하면 반복 복구를 멈추고 채팅 입력창을 안내로 바꾸며, 실패한 전송 후에도 한 번 확인한다.
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
서버도 환자별 반복 조회 대신 400명 단위로 일정 필드와 오늘 완료 기록을 묶어 읽는다.
400명 이하는 연결·알림 설정·PRN 이벤트 키를 포함해 5회 조회하며 기존 시간대별 DTO는 유지한다.
PRN 이벤트 키는 정기 진행률과 분리해 한 번에 읽고 알림을 끈 환자도 로컬 감시 기준값을 제공한다.
정상 채팅 연결에서는 반복 조회를 멈추고 복귀·장애 시 누락분을 확인한다.
채팅 입력은 입력 행만 갱신하고, 지도는 변경된 마커만 직렬로 교체한다.
외부 조회 API는 계정 등록을 마친 뒤 DB 연결을 반환한다. 건강 추천은 조회와 저장 시점에
계정 삭제·보호자 연동을 다시 검사하고, AI 대기 중 DB 연결을 보유하지 않는다.
저장 전 복약 조합이 바뀌면 409로 재조회를 요청한다. 사용자 데이터 변경 API의 잠금은 유지한다.

`MedBuddyViewModel`은 기존 화면 API를 유지하면서 처방·저장 약·일정·알림·설정·건강 추천의
독립 ViewModel에 상태 관리를 위임한다. 홈의 '연동된 환자 일정 보기'는 화면 및 음성 설정으로
이동할 뿐 선택값을 자동 변경하지 않는다. 알림을 모두 끈 연결 환자도 홈·위젯에서 조회한다.
미복약 판단은 모든 인증 mode에서 서버가 담당하며, 개발 mode의 기기는 처리 완료된 요청을 조회한다.
'10분 후 다시 알림'은 전달 건별 child Outbox, '채팅으로 알림'은 원본 건별 기존 채팅 요청을 재사용한다.
두 action 모두 서버에서 현재 권한과 유효성을 확인하며 환자의 복약 기록을 변경하지 않는다.

발표에서는 `00`부터 필요한 기능 다이어그램까지 순서대로 사용하고,
전체 `ClassDiagram`은 상세 설명이나 부록에 배치한다. 구조 변경은 `.puml`에 먼저
반영하고 대응 PNG도 함께 재생성·검사한다. 이번 갱신 대상과 검사 결과는 위에 명시했다.

아래 PNG 재생성 기록은 과거 작업 이력이며 이번 현행화의 산출물 상태가 아니다.

2026-10-08(`beta/v0.2.1`) 갱신은 클래스 그림을 코드와 다시 대조해, 코드에 없는
멤버와 삭제한 연산, 끝점이 잘못된 관계선, 빠진 `{static}` 표시를 고치고 바뀐
`.puml`의 PNG를 모두 다시 생성했다. `00`과 `01`은 한글이 빈 상자로 나오던 PNG만
다시 생성했다.

2026-10-02에는 원문 함량·제형 검증, 약명 후보 직접 확인과 계정 잠금 재시도,
위젯 완료 후 날짜별 재알림 취소를 자연어 명세와 UML에 반영했다.
`02_PrescriptionAnalysis`, `06_DoseSyncAndWidget`, `ClassDiagram`,
`HomeDoseWidget`, `OverallSystemSequenceDiagram`의 PNG도 해당 원본에서 다시 생성했다.
상세 계약은 [약명 매칭과 후보 확인](../../Medication%20Matching%20Review.md)을 참고한다.

The 2026-10-03 refactoring update preserves those medication-review and widget
flows. Prescription verification, notification protocol ownership, account-lock
cleanup and cancellation-safe request database work are reflected in the changed
sources and their regenerated PNGs. `ClassDiagram` explicitly uses the bundled
ELK layout engine; the compact feature diagrams retain Smetana. Rendered locally
with PlantUML 1.2026.8 without transmitting diagram source to a remote service.

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
