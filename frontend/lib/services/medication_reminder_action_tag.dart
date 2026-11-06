// File Name: medication_reminder_action_tag.dart
// Role: Proves that a reminder's quick action ("taken", "remind in 10 min") came from a
//   notification this app scheduled.
//
// Android delivers a tap on a notification action to the exported launcher activity, and any
// other app can start that activity with the same action and extras. A schedule payload alone
// ("schedule:<slot>:<id>:<date>") is public and guessable, so the app signs it when it schedules
// the reminder with a key only this app can read, and records a quick action only when the
// signature matches the signed-in account.

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Class Name: MedicationReminderActionTag
// Role: Signs and checks schedule reminder payloads.
// Responsibilities:
// - Keeps one random per-install key in app-private preferences, shared by every isolate.
// - Binds a tag to the account and the payload it was issued for.
// Attributes:
// - preferencesLoader: Replaceable preferences source for tests.
class MedicationReminderActionTag {
  const MedicationReminderActionTag._();

  static const String _keyName = 'medbuddy_reminder_action_key_v1';
  static const int _tagBytes = 16;
  static Future<SharedPreferences> Function() preferencesLoader =
      SharedPreferences.getInstance;

  // Function Name: sign
  // Description: Returns the tag for a schedule payload scheduled for owner.
  // Parameters: owner - account the reminder belongs to; payload - unsigned schedule payload.
  // Returns: A URL-safe tag without ':' characters.
  static Future<String> sign({
    required String owner,
    required String payload,
  }) async {
    final mac = await _mac((await _key(create: true))!, owner, payload);
    return base64Url.encode(mac.sublist(0, _tagBytes)).replaceAll('=', '');
  }

  // Function Name: verify
  // Description: Reports whether tag was issued by this app for owner and payload.
  // Parameters: owner - signed-in account; payload - unsigned schedule payload; tag - received tag.
  // Returns: False for a missing tag, a missing key or any mismatch.
  static Future<bool> verify({
    required String owner,
    required String payload,
    required String? tag,
  }) async {
    if (tag == null || tag.isEmpty || owner.trim().isEmpty) return false;
    final key = await _key(create: false);
    if (key == null) return false;
    final List<int> received;
    try {
      received = base64Url.decode(base64Url.normalize(tag));
    } on FormatException {
      return false;
    }
    final expected = (await _mac(key, owner, payload)).sublist(0, _tagBytes);
    if (received.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= received[i] ^ expected[i];
    }
    return difference == 0;
  }

  static Future<List<int>> _mac(
    List<int> key,
    String owner,
    String payload,
  ) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode('${owner.trim()}\n$payload'),
      secretKey: SecretKey(key),
    );
    return mac.bytes;
  }

  static Future<List<int>?> _key({required bool create}) async {
    final preferences = await preferencesLoader();
    // Another isolate may have written the key since this one cached its preferences.
    await preferences.reload();
    final stored = preferences.getString(_keyName);
    if (stored != null) {
      try {
        return base64.decode(stored);
      } on FormatException {
        // A damaged key is replaced below; tags issued with it stop verifying.
      }
    }
    if (!create) return null;
    final random = Random.secure();
    final key = List<int>.generate(32, (_) => random.nextInt(256));
    await preferences.setString(_keyName, base64.encode(key));
    return key;
  }
}
