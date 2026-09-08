# MedBuddy Release TODO

## v0.2.0 release blocker: restore Firebase App Check with Play Integrity

**Status:** Deferred only for direct-install functionality testing. This item
must be completed before the public v0.2.0 Google Play release.

The current off-Play beta keeps Firebase Authentication, HTTPS, trusted-host
validation, and Redis-backed rate limiting enabled, but temporarily builds the
directly installable APK and deploys the backend with App Check enforcement
disabled:

```dotenv
FIREBASE_APP_CHECK_REQUIRED=false
FIREBASE_OFF_PLAY_BETA_MODE=true
```

This exception permits a modified client operated by a valid Firebase user to
call the API without device/app attestation. Do not treat it as the final
public-release security posture. The Google Play AAB remains built with App
Check enabled.

### Completion criteria

- [ ] Create or select the Google Play Console app for `com.medbuddy.app`.
- [ ] Link its Play Integrity API configuration to the same Google Cloud/Firebase
      project used by the MedBuddy Android client and backend.
- [ ] Verify the production signing certificate SHA-256 fingerprint in Firebase
      Android app and App Check registration settings.
- [ ] Configure Firebase App Check verdict requirements for the intended v0.2.0
      distribution channels and confirm the production device-integrity level.
- [ ] Deploy the backend with `FIREBASE_APP_CHECK_REQUIRED=true` and
      `FIREBASE_OFF_PLAY_BETA_MODE=false`.
- [ ] Set the `beta-android` GitHub environment variable
      `FIREBASE_APP_CHECK_REQUIRED=true`.
- [ ] Confirm public `/ready` reports `production`, `api`, `firebase`, the
      expected Firebase project ID, and `app_check_required: true`.
- [ ] Build the protected signed artifacts from `main` and verify their signing
      certificate fingerprints and checksums.
- [ ] Install through a Google Play internal-testing track and verify login,
      authenticated API access, restart, network transitions, and temporary
      outage recovery on a physical device.
- [ ] Remove any release documentation that still describes the off-Play
      exception as active.
