import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android persists alarms across boot and package updates', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    final receiver = RegExp(
      r'<receiver\b[^>]*ScheduledNotificationBootReceiver[\s\S]*?</receiver>',
    ).firstMatch(manifest)?.group(0);
    expect(receiver, isNotNull);
    expect(receiver, contains('android:exported="false"'));
    expect(receiver, contains('android.intent.action.BOOT_COMPLETED'));
    expect(receiver, contains('android.intent.action.MY_PACKAGE_REPLACED'));
    expect(manifest, contains('ScheduledNotificationReceiver'));
  });

  // Function Name: test callback
  // Description:
  // - Verify that the manifest disables backup and that the referenced extraction rules exclude
  //   every data domain from both cloud backup and device-to-device transfer, so the encrypted
  //   dose store can never arrive on another device without its Keystore-bound key.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('Android excludes all app data from backup and device transfer', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final application = RegExp(r'<application\b[^>]*>').firstMatch(manifest)?.group(0);
    expect(application, isNotNull);
    expect(application, contains('android:allowBackup="false"'));
    expect(
      application,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );

    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    expect(rules, isNot(contains('<include')));
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp('<$section>([\\s\\S]*?)</$section>').firstMatch(rules)?.group(1);
      expect(body, isNotNull, reason: section);
      final excluded = RegExp(
        r'<exclude\s+domain="([a-z_]+)"\s+path="\."\s*/>',
      ).allMatches(body!).map((match) => match.group(1)).toSet();
      expect(
        excluded,
        {'root', 'file', 'database', 'sharedpref', 'external'},
        reason: section,
      );
    }
  });

  // Function Name: test callback
  // Description:
  // - Verify that manifest entries without any remaining caller stay removed: the legacy storage
  //   permissions, the unused map-app query and the unused widget background receiver.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('Android manifest declares no unused permission, query or receiver', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('READ_MEDIA_IMAGES')));
    expect(manifest, isNot(contains('HomeWidgetBackgroundReceiver')));
    expect(manifest, isNot(contains('android:scheme="nmap"')));
    expect(manifest, contains('android.intent.action.TTS_SERVICE'));
    expect(manifest, contains('android.intent.action.PROCESS_TEXT'));
  });
}
