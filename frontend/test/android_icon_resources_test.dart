// File Name: android_icon_resources_test.dart
// Role: Keeps the Android launcher and notification icons in the form launchers and the
//   status bar need: an adaptive launcher icon whose layers exist at every density, and a
//   transparent small icon used by both local reminders and FCM notifications.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';
const _densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4};

// Function Name: _pngSize
// Description: Reads width and height from a PNG header and fails on anything else.
// Parameters: - file (File): The image to read. Returns: (int, int): Width and height in pixels.
(int, int) _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.sublist(1, 4), 'PNG'.codeUnits, reason: file.path);
  final header = ByteData.sublistView(bytes, 16, 24);
  return (header.getUint32(0), header.getUint32(4));
}

// Function Name: main
// Description: Registers the adaptive icon, density and small-icon checks.
// Parameters: None. Returns: No value.
void main() {
  test('the launcher icon is adaptive with foreground and monochrome layers', () {
    final xml = File('$_res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
    expect(xml, contains('<adaptive-icon'));
    expect(xml, contains('@mipmap/ic_launcher_foreground'));
    expect(xml, contains('@mipmap/ic_launcher_monochrome'));
    expect(xml, contains('@color/ic_launcher_background'));
    for (final MapEntry(key: name, value: density) in _densities.entries) {
      final size = (108 * density).round();
      for (final layer in ['ic_launcher_foreground', 'ic_launcher_monochrome']) {
        expect(_pngSize(File('$_res/mipmap-$name/$layer.png')), (size, size));
      }
      // Android 7 and older still use the legacy square icon.
      expect(File('$_res/mipmap-$name/ic_launcher.png').existsSync(), isTrue);
    }
  });

  test('reminders and FCM pushes use the transparent small icon', () {
    for (final MapEntry(key: name, value: density) in _densities.entries) {
      final size = (24 * density).round();
      expect(_pngSize(File('$_res/drawable-$name/ic_stat_medbuddy.png')), (size, size));
    }
    expect(
      File('lib/services/notification_service.dart').readAsStringSync(),
      contains("AndroidInitializationSettings('@drawable/ic_stat_medbuddy')"),
    );
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('com.google.firebase.messaging.default_notification_icon'));
    expect(manifest, contains('@drawable/ic_stat_medbuddy'));
  });
}
