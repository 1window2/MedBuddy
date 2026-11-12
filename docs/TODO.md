# MedBuddy Release TODO

The 1.0.0 line runs on `beta/v1.0.0` from `v0.2.5-beta` (`main` at `5b156c9`). This
file lists open items only, sorted by priority. Finished items were removed on
2026-11-12; they remain in the git history, the release notes and the
[decision log](MedBuddy%20-%20Decision%20Log.md). Changes are listed in the
[1.0.0 notes](releases/v1.0.0.md).

| Priority | Meaning |
| --- | --- |
| P0 | Blocks the 1.0.0 release. |
| P1 | To finish before 1.0.0: device checks of the main flows on the release build, and the exhibition. |
| P2 | Security and operations hardening; owner checks. |
| P3 | Owner decisions and known limits that matter only with more users or data. |
| P4 | Not possible with the current devices, minor details and the product backlog. |

## P0: blocking the 1.0.0 release

- [ ] Google Play distribution with App Check (Play Integrity). The owner chose both
      Google Play and the GitHub APK on 2026-11-07, so the criteria below block 1.0.0;
      if distribution is narrowed to the GitHub APK, this item and the next leave P0.
      Until then the off-Play build runs without App Check and production accepts
      anonymous sign-in (`FIREBASE_APP_CHECK_REQUIRED=false`,
      `FIREBASE_OFF_PLAY_BETA_MODE=true`): a modified client with a valid Firebase
      user can call the API without attestation, and daily quotas bound the cost per
      account and per address, not across many addresses. The Play AAB is already
      built with App Check on. `com.medbuddy.app` is registered with Play Integrity in
      Firebase (seen on 2026-10-02); the owner has no Google Play developer account
      yet. Completion criteria:
  - [ ] Create or select the Google Play Console app for `com.medbuddy.app`.
  - [ ] Link its Play Integrity API configuration to the Google Cloud/Firebase
        project used by the Android client and the backend.
  - [ ] Verify the production signing certificate SHA-256 fingerprint in the
        Firebase Android app and App Check registration.
  - [ ] Configure the App Check verdict requirements for the public distribution
        channels and confirm the production device-integrity level.
  - [ ] Configure the read-only preflight identity and the protected `beta-android`
        variables, then pass `check_release_app_check.py` against the live project
        (see [the setup instructions](Production%20Deployment.md#protected-android-app-check-preflight)).
  - [ ] Deploy the backend with `FIREBASE_APP_CHECK_REQUIRED=true` and
        `FIREBASE_OFF_PLAY_BETA_MODE=false`.
  - [ ] Set the `beta-android` environment variable `FIREBASE_APP_CHECK_REQUIRED=true`.
  - [ ] Confirm public `/ready` reports `production`, `api`, `firebase`, the expected
        Firebase project ID and `app_check_required: true`.
  - [ ] Build the protected signed artifacts from `main` and verify their signing
        certificate fingerprints and checksums.
  - [ ] Install through a Google Play internal-testing track and verify sign-in,
        authenticated API access, restart, network changes and outage recovery on a
        physical device.
  - [ ] Remove release documentation that still describes the off-Play exception as
        active.
- [ ] Design: how the GitHub APK passes App Check once production requires it (Play
      Integrity recognises only Play-distributed builds).
- [ ] A final privacy policy and consent for health data; the in-app data-use guide
      does not replace them (Beta Scope). Owner and legal.
- [ ] A larger hospital API quota: an operating account on the public data portal
      (requested by registering a use case). The development account (valid to
      2028-10-01, 1,000 calls per operation a day) leaves a server budget of 800 calls
      a day per operation shared by all users, and one specialty search can cost up
      to 41 requests. One free account can spend the detail budget in about 67
      searches inside its own 120-search quota, after which hospital search answers
      503 for everyone until midnight. If the quota is not raised, the owner decides
      whether to charge detail calls per account, which would also limit ordinary
      users to a few searches a day.

## P1: before 1.0.0

Device checks on the release build. The last pass (2026-11-12) is summarised in the
[1.0.0 notes](releases/v1.0.0.md#device-and-operations-checks-2026-11-12).

- [ ] With the next signed build on the phone: a reminder's Taken pressed while the
      app is closed shows the new home count at once, and the server gets one record
      (fixed on 2026-11-12, checked on the emulator).
- [ ] Medication reminder actions on a locked screen, after a reboot and with
      battery saver; an offline completion failure and its retry; correcting one dose
      after an accidental Taken.
- [ ] Turning medication notifications off removes pending alarms and medication
      quick actions already shown, and keeps caregiver and chat alerts.
- [ ] A caregiver's slot-check request: Taken from a locked phone, a request arriving
      after midnight, and an offline tap updating the widget.
- [ ] Around midnight: the first launch after the day changes, a dose tapped right
      after midnight, a snooze across midnight, the 12-hour reminder task and sign-out
      while it runs, and offline after midnight.
- [ ] Without network at start: caregiver alerts after an offline start, and push
      registration after a cold start. The Galaxy Note10 carries adb over its network,
      so this needs a cable or the emulator.
- [ ] After an update: reminders scheduled by an earlier build, and the periodic
      WorkManager tasks before the first launch (only the widget path was exercised).
- [ ] Caregiver alerts: the missed-dose alert withdrawn after a dose, and the server's
      missed-deadline path with the patient or caregiver app force-stopped and with a
      transient FCM failure.
- [ ] Prescription capture with the privacy filter on a real prescription, including
      a table whose name cell sits right of its label (fixed on 2026-11-11 and checked
      with a mock prescription), the clean-up of picked photo copies, and saving
      several identified pills.
- [ ] Message deletion between two devices: reconnect, offline failure, delivered
      previews and the 24-hour deadline.
- [ ] Session: a network loss during a token refresh keeps the session; a 401 in chat
      signs out; ending the session with a pushed screen open.
- [ ] Poster, and feedback gathered for the graduation exhibition (2026-11-26 to
      11-27).

## P2: security and operations

- [ ] A Postgres role without superuser rights for the API and catalog jobs (security
      audit); only the migration needs the owner role. The code is ready
      (`scripts/provision_database_roles.py`, opt-in through
      `MEDBUDDY_APP_DB_USER`/`MEDBUDDY_APP_DB_PASSWORD`, see Production Deployment);
      production needs the owner to add the two settings.
- [ ] Keep at least one database dump off the production host.
- [ ] Read the data.go.kr daily quotas of the production key for the MFDS eDrug,
      drug-approval and pill-image operations and the NEMC pharmacy location
      operation. MFDS lookups have no shared daily budget: one `/identify` can make up
      to 16 provider calls and only per-account and per-IP limits apply. Pharmacy
      lookups stop at 800 a day; raise `PHARMACY_API_DAILY_REQUEST_BUDGET` if the
      quota is higher.
- [ ] Rate-limit store (128 MB, noeviction; a full store makes the limiter answer 503
      to everyone): read `INFO memory` and `DBSIZE` on rate-limit-redis, add an alert
      as `used_memory` nears `maxmemory`, and check whether Cloudflare forwards full
      IPv6 client addresses (quotas count an IPv6 address as its /64).
- [ ] Signed workflow: whether the deployment review shows the dispatch inputs, which
      branches the `beta-android` policy still allows (remove finished `beta/v0.2.x`
      entries), and branch protection for `beta/v1.0.0`.
- [ ] Push tokens of a user disabled by the operator keep receiving pushes until the
      account is deleted, and the account owner has no "sign out other devices"
      action.

## P3: owner decisions and known limits

- [ ] `SAVED_MEDICATION_MAX_PER_ACCOUNT` (300) also counts stopped regimen versions,
      so frequent edits over years can reach it.
- [ ] The missed-dose scan re-reads every slot completed before its deadline on each
      15-second pass for the rest of the day, two to four queries per patient and
      slot. Negligible at this size; remembering "complete at the deadline" would
      change what an undo after the deadline does.
- [ ] A failed local reminder save turns the reminder off by design instead of
      restoring it.
- [ ] Ranking fuzzy catalogue candidates by matched fragments raised recall on a
      synthetic catalogue from 5 to 189 of 200, but every name it moves from
      `unverified` to `llm_catalog_candidate` (0.86–0.89) stops requiring user review,
      because the client flags only `unverified` or a confidence below 0.75. Needs a
      check on the production catalogue and a decision on review flagging. On the
      local catalogue window it turned correct automatic matches into review lists
      without the true product, so it must not be applied as is.
- [ ] Rate-limit values (including 120 per minute for per-item deletes), retention of
      dose-sync and tombstone rows, and HTTP 403 wording and retry behaviour before App
      Check is enabled.
- [ ] Database: 31 of 64 secondary indexes have no query that uses them; a stored
      course-end column and `pg_trgm` would need migrations. CI does not run the full
      test suite on PostgreSQL (only the migration round trip and the PostgreSQL
      integration tests) or fuzzy recall on a realistic catalogue; complete
      ORM/migration drift coverage and pinning the server strings the client matches
      are open.
- [ ] Both CI workflows report a job named `build`. Unique names change the
      required-check names and need a branch-protection change by the owner.
- [ ] Dependabot does not watch the `gradle` and `docker` ecosystems (pull-request
      volume).
- [ ] Further APK size reduction (arm64 only, compressed native libraries or per-ABI
      splits) changes device support or update mechanics.
- [ ] Widget on a 160 dpi screen (visual): the one-row widget (250 x 48 dp, patient,
      normal text, missed dose) cuts the save-state line by 2 px when the missed-dose
      note wraps to two lines (CI run 42317116065 on `e7bef59`). It fits on the
      devices checked (420 dpi emulators, Galaxy Note10); 240 and 320 dpi are not
      checked. A different row layout would change the widget's look.
- [ ] Manual and pill-photo registration offer four rhythms (every day, every other
      day, once a week, once a month); others such as named weekdays need
      prescription registration.
- [ ] A weekly prescription often prints the number of doses as its total days ("4"
      for four weeks). The review screen shows the resulting dose days so the user can
      correct it, but the value is not guessed.
- [ ] Dropping a pill-photo crop for a low-score multi-pill image needs real
      photographs before the rule changes.

## P4: low priority

- [ ] Slot-check details left as they are: two devices with stale caches can each
      confirm the same slot from a request, and the server then posts a second
      "복용을 기록했습니다" message, as the chat Taken reply always has; the request
      notification stays until read or tapped even when the dose was recorded in the
      app or widget; the notification button reads "복용 완료" and the reminder
      "복용했어요".
- [ ] The user guide keeps an unused photo (`notification_settings_2026-10-22.png`)
      in its verification hashes.
- [ ] Not checked on a device: a shared place missing from the list, and the closed
      and overnight wording (covered by tests).
- [ ] Native map marker recovery after a partially failed marker addition, and marker
      retry; recovery of the dose store on a real Keystore.
- [ ] Class diagrams: align stereotypes and package placement between the overall and
      feature diagrams when those diagrams next change.
- [ ] Not possible with the current devices: Android 16 on a phone (exercised on an
      Android 16 emulator on 2026-10-15), device-to-device transfer (the extraction
      rules exclude all app data; needs two phones), two physical phones, and more
      than three sessions on one link.
- [ ] A short task-count usability study with older adults or proxy users: taps, text
      entry, completion time, error recovery, large-text layout, TalkBack labels and
      one-handed reach for the medication, caregiver and chat flows.
- [ ] Product backlog, outside the 1.0.0 scope. Rule: prefer removing a repeated
      patient action over adding a feature, and never infer a completed dose from weak
      evidence.
  - [ ] Caregiver escalation levels with explicit consent, quiet hours, cooldowns,
        acknowledgement and deduplication (no notification flooding, which causes
        alarm fatigue).
  - [ ] A remotely controlled maintenance notice with a start and end time and retry
        guidance before a planned interruption.
  - [ ] The evidence-gated intake automation stages in
        `MedBuddy - Medication Intake Automation Roadmap.md`: a camera or model may
        preselect a dose, but ambiguous identity, count or timing needs one clear
        confirmation and never writes a completion record.
  - [ ] Samsung scroll capture (long screenshot) does not work in the app ("이 화면에서는
        스크롤 캡처를 사용할 수 없어요"), because Flutter draws everything in one
        FlutterView the system cannot scroll. Supporting it means implementing
        Android 12's scroll capture callback for the Flutter view, and Samsung's
        capture may not use it. Reported by a tester on 2026-10-26.
