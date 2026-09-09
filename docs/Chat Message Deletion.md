# Chat Message Deletion

## Deletion policy

- Applies to the experimental medication-context chat on `beta/v0.2.0`.
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
