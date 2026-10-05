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
조회 자체는 읽음 상태를 변경하지 않는다. DB 마이그레이션은 필요하지 않다.

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

읽음 표시는 대화를 확인한 상태이지 실제 복용·진료·메시지 이해 여부를 검증한 결과가 아니다.
Firebase 운영 푸시 도착은 로컬 인증 비활성 데모와 별도 검증이 필요하다.

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
in retry comparison. Explicit care retry IDs survive another failed message; dose
recording retains its separate operation identities. A disposed composer cannot
publish a late result or clear another conversation's draft. Cancellation does not
undo a message that the server has already stored.

Changing account, link or patient replaces the conversation session and its
adapters, draft and history. Updating settings or re-entering the same conversation
keeps that session and draft. No backend authorization, message wire fields,
read-receipt meaning or retry/idempotency contract changes with this refactor.

관련 UML: [읽음·알림 진입 시퀀스](UML/sequence/ChatReadState.puml),
[연동·알림 클래스](UML/class/04_CaregiverNotifications.puml).
