# 채팅 읽음 상태와 알림 진입

## 세 가지 표시의 구분

- **채팅 목록 숫자**: 해당 연동에서 내가 안 읽은 상대 메시지 수다. 0개는 숨기고 100개 이상은 `99+`로 표시한다. 목록만 열어서는 메시지를 읽음 처리하지 않는다.
- **보낸 메시지 옆 1**: 상대의 `read_at`이 없는 내 메시지에만 표시한다. 서버 읽음 이벤트 또는 재조회로 읽음을 확인하면 숫자만 없애고 전송 시각은 남긴다. 접속 상태나 알림 수신만으로 지우지 않는다.
- **알림함의 안 읽음**: 계정별 기기 알림 기록의 상태다. 채팅 목록 개수·메시지 읽음과 별개이며 알림함의 모두 읽음으로 채팅을 읽음 처리하지 않는다.

## 서버 계약

`GET /api/v1/chat/links/{link_id}/unread-count`는 기존 `unread_count`와 함께
`first_unread_message_id`를 반환한다. 안 읽은 메시지가 없으면 첫 ID는 `null`이다.
활성 연동 참여자 권한을 확인하고 같은 집계 쿼리로 개수와 첫 ID를 구한다.
자신이 보낸 메시지, 모두에게 삭제된 메시지, 해당 사용자에게 숨겨진 메시지는 제외한다.
조회 자체는 읽음 상태를 변경하지 않는다. 이 읽음 요약 계약 자체에는 DB 마이그레이션이 필요하지 않다.

앱은 누락된 첫 ID를 구버전 응답으로 허용하고 최근 이력의 `read_at`으로 보완한다.
개수 조회 실패는 대화 진입을 막지 않으며, 목록에서는 확인하지 못한 개수를 0으로 단정하지 않는다.

## 대화 위치와 읽음 처리

1. 처음 진입할 때 최근 이력과 미확인 요약을 읽고, 읽음 갱신 전에 첫 미확인 ID를 보관한다.
2. 역방향 목록의 0 위치를 최신 메시지로 사용해 높이가 다른 약·병원 카드 때문에 중간에서 멈추지 않게 한다.
3. 첫 미확인 메시지 앞에 `여기까지 읽음`을 두고 같은 진입 동안 기준을 유지한다. 50개보다 오래된 경계는 `이전 대화 보기`로 찾아갈 수 있다.
4. 앱이 전경이고 채팅이 현재 경로이며 최신 위치에 있을 때 상대 메시지를 읽음 처리한다. 과거 이력·약 선택·상세·다른 앱을 보는 동안에는 새 메시지를 자동으로 읽음 처리하지 않는다.
5. 중복 읽음 요청을 합치고 성공한 마지막 ID를 기억한다. 지연된 이력 응답이 이미 확인된 `read_at`을 되돌리지 않게 병합한다.

대화 목록 개수는 진입·새로고침·대화 복귀와 기존 활성 15초 갱신에 맞춰 조회한다.
별도 고빈도 폴링은 추가하지 않는다. 실시간 메시지 수신과 장애 복구 정책은
[클라이언트 갱신 정책](MedBuddy%20-%20Client%20Refresh%20Policy.md)을 따른다.

## 알림으로 열기

- 알림의 수신 계정·유형·시간대와 활성 연동을 확인한다. 알 수 없는 푸시 유형과 잘못된 일정 시간대는 이동 대상으로 사용하지 않는다.
- `LinkedChatEntryUI`가 연동 정보를 읽어 실제 환자 ID와 상대 이름을 넘긴다. 알림으로 들어온 환자에게 보호자 질문 문구가 표시되지 않도록 기본 역할을 추정하지 않는다.
- 같은 채팅 알림을 다시 누르면 기존 경로로 돌아가 누락분을 확인하고 최신 위치로 이동한다. 입력 중인 초안·첨부와 최초 읽음 경계는 유지한다.
- 열린 본인 일정에 다른 시간대 알림이 오면 그 시간대로 이동한다. 보호자 일정·채팅 진입 시 현재 계정의 글자·언어 설정을 유지한다.
- 로그인 복구를 기다리는 동안 계정이 바뀌면 이전 계정의 대기 중 알림을 실행하지 않는다.

## 연동별 알림 묶음

- 미확인 조회에 `include_notification_preview=true`를 명시한 경우에만 알림용
  `notification` 요약을 함께 반환한다. 기존 목록·읽음 경계 조회는 본문 요약을
  요청하지 않는다. 서버가 현재 미확인 개수와 최근 최대 세 건의 짧은 미리보기를
  구성하며 본인 메시지·숨김·모두에게 삭제된 메시지는 제외한다.
- 일반 채팅은 수신 계정과 연동으로 만든 동일한 그룹 키를 푸시와 로컬 알림에 사용한다.
  Android는 같은 태그의 알림을 갱신하고 iOS는 같은 대화 묶음 식별자를 사용한다.
  기기에 받은 메시지를 계속 쌓아 개수를 추정하지 않는다.
- 내용 숨김 설정에서는 상대 이름과 미리보기를 숨기고 일반 새 메시지 안내를 쓴다.
  복약 기록 공유는 상세 표시가 허용돼도 약명·기간·복용 건수를 알림에 넣지 않는다.
- 서버 읽음 성공 후 해당 계정·연동의 운영체제 알림을 정리한다. 로컬에서 이미
  확인한 최신 메시지보다 오래된 요약과 읽은 범위의 늦은 알림은 다시 표시하지 않고,
  읽음 요청 뒤 도착한 더 최신 메시지 알림은 지우지 않는다.
- 알림 묶음 갱신은 채팅 메시지·기기 알림함의 읽음 의미를 합치지 않는다.
  이미 외부에 전달된 미리보기를 회수하거나 모든 기기의 알림 삭제를 보장하지 않는다.

읽음 표시는 대화를 확인한 상태이지 실제 복용·진료·메시지 이해 여부를 검증한 결과가 아니다.
Firebase 운영 푸시 도착은 로컬 인증 비활성 데모와 별도 검증이 필요하다.

## Android 확인 요청의 복용 완료

보호자가 환자에게 보낸 저장된 `slot_check_request` 중 서버의 오늘 날짜와 정기
시간대가 확인된 요청만 실행 가능한 알림 대상이다. 일반 문구나 PRN 알림을 복용
명령으로 해석하지 않는다. 서버는 전송 직전 메시지·연동·계정·읽음 상태를 확인하고,
`supports_slot_check_actions`를 등록한 Android 토큰에만 `action_version=1`과
원래 날짜·환자·연동·메시지 식별자를 담은 data-only 푸시를 보낸다. 구버전·미지원
기기는 기존 OS 알림을 유지한다. 전경의 연동 메시지 감시도 보호자→환자 역할과
오늘 날짜를 확인하며 같은 실행 문맥을 사용한다.

실행 알림은 대화 묶음 대신 `chat:<link>:<message>`별 태그를 써 다른 요청의 날짜·
시간대 버튼으로 바뀌지 않게 한다. 본문 선택은 기존 활성 연동 확인 후 채팅을 열고,
Android의 `복용 완료` 버튼은 화면을 열지 않고 백그라운드에서 처리한다. 읽음 처리와
복용 기록은 별개다. 표시 시와 실행 시 현재 기기 계정·오늘 날짜를 검사하며,
환자·수신자 불일치나 잘못된 이벤트 식별자는 거절한다.

`SlotCheckNotificationService`는 현재 계정의 암호화 `DoseOutboxStore`만 사용한다.
오늘 캐시가 없으면 검증된 14일 일정 창으로 복원하거나 조회하며, 요청 중 자정이
지나도 원래 날짜를 오늘로 바꾸지 않는다. 해당 시간대의 실제 일정과 처방 revision을
대상으로 완료를 기록한다. 빈 일정·잘못된 약 ID·겹치는 차단 요청은 새 기록을 막는다.
버튼 소비 표식과 전송 대기는 한 SQLite 트랜잭션으로 저장한다. 같은 요청을 다시
눌러도 이후 사용자가 취소한 복용을 되살리지 않는다.

기기 저장 후 알림·해당 날짜의 재알림을 정리하고 기존 `DoseSyncService`와
WorkManager로 전송한다. 예약·인증·통신 실패는 이미 저장한 요청을 버리지 않으며,
기기 저장 성공은 서버 반영 완료를 뜻하지 않는다. 서버는 환자 소유권·원래 날짜·
처방 revision과 요청 ID를 검증한다. 활성 연동이면 기존 복용 채팅을 함께 기록하고,
그사이 연동이 없어졌다면 본인 복용 기록만 반영한다. 다른 사람의 연동에 대한
권한 오류는 무시하지 않는다. 오프라인 대기와 거절 처리는 기존 복용 동기화를 따른다.

배포에는 `e6b4d2a9f031` 다음 `f7a2c9e4b610` 마이그레이션이 필요하다.
기존 토큰의 새 capability는 기본 false이며 지원 앱의 Android 재등록 때만 켜진다.
구버전 재등록·앱 다운그레이드는 다시 false로 저장한다. DB와 서버를 먼저 갱신한 뒤
앱을 배포하며 실제 FCM 수신·잠금 화면·프로세스 종료 상태는 별도 기기 검증 대상이다.

설계 연결: [복용 동기화](UML/sequence/OfflineDoseSync.puml),
[채팅 진입](UML/sequence/ChatReadState.puml),
[연동·알림 클래스](UML/class/04_CaregiverNotifications.puml).

## Conversation-state ownership

`LinkedChatHistoryViewModel` owns one immutable account/link scope: coalesced history
recovery, backwards pagination, monotonic read receipts, deletion evidence and
failure-only polling. The UI supplies visibility/latest-position predicates and
rendering callbacks; it cannot mutate the history snapshot. Authenticated REST and
realtime adapters remain borrowed resources owned by the conversation presentation.
Late responses and wrong-link events cannot publish into a disposed history owner.

`LinkedChatComposerViewModel` independently owns outgoing concurrency, the failed
request identity and immutable `ChatMessageDraft` payloads. The UI keeps text-field
controllers, attachment selection, navigation, localized feedback and care-share
retry display metadata. Medication IDs compare without regard to order for the
existing retry contract, while their primary attachment and wire order remain
unchanged. Structured kind, slot, pharmacy, hospital and selected date all participate
in retry comparison. Unsaved medication references compare their full serialized
snapshots in attachment order, separately from saved-medication IDs; they are not
dose targets. Explicit care retry IDs survive another failed message; dose
recording retains its separate operation identities. A disposed composer cannot
publish a late result or clear another conversation's draft. Cancellation does not
undo a message that the server has already stored.

Changing account, link or patient replaces the conversation session and its
adapters, draft and history. Updating settings or re-entering the same conversation
keeps that session and draft. No backend authorization, message wire fields,
read-receipt meaning or retry/idempotency contract changes with this refactor.

관련 UML: [읽음·알림 진입 시퀀스](UML/sequence/ChatReadState.puml),
[연동·알림 클래스](UML/class/04_CaregiverNotifications.puml).
