# Durable chat delivery

This design note supersedes the ordinary-chat BackgroundTasks portion of the
older UML sequence and rendered diagrams. Caregiver completion/missed-dose
delivery remains in its own outbox; the two queues are not conflated.

## Ownership and flow

- `ManageLinkedChat` saves a user message and its `ChatNotificationJob` in the
  same transaction. The message primary key is also the job primary key.
  Duplicate requests reuse history and never create a second job.
- Explicit patient dose receipts enqueue in the same transaction as the dose
  and receipt, including the `SyncDose` outer-transaction path. Internal
  caregiver-generated completion messages retain their existing notification
  path and do not generate another ordinary-chat job.
- The HTTP router broadcasts committed messages but does not own push delivery.
- `ChatNotificationWorker`, owned by the application lifespan, polls every five
  seconds. `ProcessChatNotifications` uses separate short-lived sessions for
  claims, delivery and result recording. Blocking work stays in the bounded
  thread pool; no DB session crosses an asynchronous policy wait.
- `DispatchChatMessageAlert` rechecks the active link, recipient membership,
  deletion/read state, notification preference, sensitive-preview policy and
  device tokens immediately before sending.

## Delivery semantics

Delivery is **at least once**, not exactly once. A crash after FCM acceptance but
before result persistence, or a partial multi-device failure, can duplicate a
push. Retries preserve the existing `chat:<link>:<message>` event ID. A recorded
completion means the dispatch policy finished; no eligible token, a disabled
preference or a hidden/read message can deliberately produce zero pushes.

Atomic conditional updates claim jobs for five minutes. Attempts act as fencing
tokens so an old worker cannot overwrite a newer attempt's state; they do not
recall an in-flight FCM request. Failures retry with backoff, for at most eight
delivery attempts, and jobs older than 24 hours are discarded. These limits
avoid indefinite delivery of stale chat prompts. Pending and dead jobs retain
only IDs/state, not copied message previews or tokens.

Existing presence and burst-control policy remains: a connected recipient or a
denied per-recipient/link cooldown suppresses that job. Quota-store failures
retry rather than discard the job. Both realtime presence and broadcasting are
still process-local; this change does not permit multiple API workers. The
read-state check is not atomic with external delivery: a push already submitted
cannot be recalled when the recipient reads or deletes the message.

Deleting a message or recipient account cascades to its jobs; existing chat
retention therefore bounds job retention. Old messages are not backfilled.

## Deployment

Apply Alembic `b3a7d9e2f601` (after `6d4f8a2c9301`) before starting the new
backend. Stop old workers during rollout and follow the backup/readiness
procedure. Rolling this migration back drops pending delivery work but leaves
chat history and medication records unchanged; coordinate rollback with the
matching older backend. No production migration is performed by this change.

## Acceptance

Automated tests cover transaction rollback, duplicate sends, restart recovery,
transient/partial delivery failures, abandoned claims, stale-result fencing,
expiry/retry limits, privacy/consent changes, cleanup, and outer dose-sync
transactions. The migration preservation rehearsal runs in SQLite and in the
PostgreSQL 16 CI job. Real FCM and two-device acceptance remain deferred.

Local verification: **675 backend tests passed, 2 PostgreSQL-specific tests
skipped**, with 21 passing subtests; `git diff --check` passed. The 19 new durable
delivery cases use synthetic data and injected push boundaries, not real FCM.
