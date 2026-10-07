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
}
