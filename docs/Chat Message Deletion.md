# Chat Message Deletion

## Deletion policy

- Applies to the medication-context chat.
- Select messages and confirm the deletion scope before deleting them.
- **Delete for me:** available for incoming and outgoing messages at any age.
  The selection disappears only for this participant, across their devices.
- **Delete for everyone:** only the sender can redact a message, strictly
  within 24 hours of sending, according to the server clock. If any
  selected message is ineligible, the entire shared-deletion request fails.
- Shared deletion leaves a "This message was deleted" placeholder. Medication
  cards, dose snapshots, pharmacy snapshots and message text are removed.
- Deletion does not change saved medications, completion records, schedules,
  notification settings, or the patient-caregiver link.
- Deletion cannot be undone. Already delivered notification previews and
  screenshots cannot be recalled.

## 복사와 삭제 표시

- 메시지를 길게 누르면 복사 또는 삭제 선택 메뉴를 연다. 복사는 삭제되지 않은
  메시지의 현재 본문만 클립보드에 넣으며 첨부 카드 전체나 숨겨진 문맥을 내보내지 않는다.
- 메뉴가 열린 사이 메시지가 삭제·숨김 처리되거나 대화 세션이 바뀌면 이전 본문을
  복사하지 않는다. 복사 실패는 별도 안내하며 메시지와 읽음 상태는 변경하지 않는다.
- 모두에게 삭제된 메시지는 삭제 아이콘과 구분된 안내 문구만 표시하고 본문·약·
  복약 기록·병원·약국 첨부를 다시 렌더링하지 않는다. 나에게서만 삭제한 메시지는
  기존처럼 해당 참여자 목록에서 숨긴다. 삭제 범위·24시간 제한·서버 검증은 유지한다.
- 이미 클립보드나 외부 앱에 복사한 본문은 이후 채팅 삭제로 회수할 수 없다.

## Architecture and data

- The existing UI -> Control -> Repository/Entity structure is preserved.
  The backend checks participant identity, sender ownership and the deadline.
- Private deletion keeps the peer's record under the existing retention policy;
  it is not immediate physical erasure. Shared deletion removes live message
  content and attachments, retaining only a deletion marker and basic metadata.
  Existing backups follow their own retention policy.
- History, unread counts, exports and real-time updates respect deletion scope.
  Delayed responses must not restore deleted content in the open chat screen.
- Apply migration `c2e4a6b8d901` before deploying the new client. Existing
  messages are preserved on upgrade. A downgrade cannot restore shared-deleted
  content and makes privately hidden records visible again.

## Verification scope

Automated tests cover deletion permissions, the 24-hour limit, data consistency,
real-time updates and the selection UI. Production PostgreSQL concurrency and
signed physical-device/offline/push behavior still require release verification.
