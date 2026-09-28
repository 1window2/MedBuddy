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
