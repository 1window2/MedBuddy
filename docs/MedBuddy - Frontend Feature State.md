# Frontend feature state isolation

The first extraction from the shared `MedBuddyViewModel` library is health
recommendation presentation state. The existing UC-10 and overall sequence remain
unchanged at the API boundary; this note refines the frontend ViewModel step in
the class and sequence diagrams.

`HealthRecommendationUI` calls the compatibility facade in `MedBuddyViewModel`.
The facade owns an independent `MedBuddyHealthRecommendationViewModel`, which
delegates requests to the existing patient-scoped `CheckHealthRecommendation`.
The control still owns API adaptation; no authorization or HTTP logic moves into
the presentation model. The parent disposes the borrowed control exactly once.

The feature model owns loading, confirmed-empty, result and message state. It is
an imported library, not a `part` extension, so it cannot access unrelated private
schedule, prescription or reminder state. Its notifications are bridged to the
existing health feature channel and parent listeners for compatibility. Health
feedback no longer overwrites the global prescription/reminder status message;
the health screen reads `healthRecommendationStatusMessage` instead.

Each request captures a generation and language. Only the newest generation may
publish a result, empty state, failure or loading completion. Disposal invalidates
all pending completions. This does not cancel server work or change backend
recommendation caching. Other five feature extensions remain shared-state code;
this is an incremental extraction, not a claim of complete frontend decoupling.

Regression coverage includes reversed completion, an old failure during a newer
request, disposal, feature notification isolation, and existing health UI tests.

## Saved medications

The saved-medication feature now owns its list, loading generation and feedback
in a separate library. A compatibility-only facade forwards existing methods;
it owns no list state. Cross-feature coordination uses explicit schedule-refresh
and reminder-synchronization callbacks, preserving existing overridden methods
and refresh sequencing. Shared deletion results live outside the facade library
to avoid a circular import. Controls remain borrowed and parent-disposed.

Only the latest list request may publish. Confirmed deletion invalidates earlier
reads; clearing account data or disposing the feature also invalidates late list
and image completions. Deletions publish a saved-medication update explicitly.

## Schedules

The schedule feature owns courses, loading/error state and request generations.
The facade forwards screen operations and supplies a read-only durable-queue
provider. Queue projection uses an explicit operation that does not claim a
fresh server read. Reminder reconciliation reads the feature's freshness flag;
account clearing invalidates pending reads. Slot interpretation is a shared pure
policy rather than a private helper inside prescription processing.

The facade coalesces concurrent refreshes and may reuse a successful same-day
schedule/reminder read for less than 15 seconds on tab revisits. Explicit refresh
still reads the server, and schedule changes invalidate this reuse window.

## Reminders

Reminder settings and read freshness are owned by the reminder feature. Schedule
lists, schedule freshness and user settings are supplied through read-only
callbacks, not mutable sibling state. The facade retains the coordination point
for post-save reconciliation. Reminder save/rollback, privacy and snooze-preserving
refresh semantics are unchanged. Superseded or disposed loads cannot publish.

## User settings and application flows

Settings now own their immutable setting value in an independent library.
Persistence still uses `ManageUserSetting`; local notification policy and explicit
refresh callbacks preserve the existing save behavior. The facade reads settings
through an accessor rather than sharing a mutable field. Disposed settings reads
cannot publish or initiate subsequent refresh work.

Cross-feature recovery, account deletion and overview/schedule refresh remain
application orchestration, not settings state. The application-flow adapter
preserves the contributors' same-day 15-second schedule reuse, in-flight refresh
coalescing and explicit retry behavior. Widget publication retains configuration
deduplication while reading the isolated settings value.

At the native scheduling boundary, date-specific plans are reconciled with
pending notifications instead of cancelling and rebuilding every slot. Unchanged
bookings and snoozes survive; scheduling, snoozing and cancellation are serialized
within the service. See the [client refresh policy](MedBuddy%20-%20Client%20Refresh%20Policy.md)
for cache scope, widget publication and recovery behavior.
