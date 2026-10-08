// File Name: android_widget_contract_test.dart
// Role: Pin the names and JSON keys shared by the Dart widget service and the Kotlin widget provider,
//   because no workflow runs the Android instrumented tests that would otherwise cover them.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/dose_widget_state.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/services/dose_home_widget_service.dart';

const _kotlinDirectory =
    'android/app/src/main/kotlin/com/example/medbuddy_frontend';

// Keys the Kotlin provider reads only from JSON it writes itself: the per-widget patient and page
// selections ("context", "patient") and the widget number stored with a queued action ("widget").
const _nativeOnlyKeys = {'context', 'patient', 'widget'};

// Function Name: _stringConstant
// Description:
// - Read the value of a Kotlin `const val` string declaration from source text.
// Parameters:
// - source (String): Kotlin source text.
// - name (String): Constant name to look up.
// Returns:
// - String?: The declared value, or null when the constant is not declared as a string literal.
String? _stringConstant(String source, String name) => RegExp(
  'const val $name = "([^"]*)"',
).firstMatch(source)?.group(1);

// Function Name: _publishedKeys
// Description:
// - Build a patient-owned and a caregiver widget state and collect every key of the published
//   view, including the keys of its slot pages and of its per-patient entries.
// Parameters:
// - None.
// Returns:
// - Set<String>: Keys present in the JSON the Dart side stores for the native widget.
Set<String> _publishedKeys() {
  final now = DateTime.utc(2026, 9, 21, 1);
  const medication = MedicationSchedule(
    medicationID: '91',
    medicationName: 'contract medicine',
    scheduleSlotKeys: ['morning', 'evening'],
    slotStatuses: {'morning': false, 'evening': false},
  );
  final snapshot = {
    'date': doseWidgetDay(now),
    'schedules': [medication.toJson()],
  };
  final own = DoseWidgetState.build(
    owner: 'patient-a',
    cache: snapshot,
    operations: [],
    previous: {},
    now: now,
  ).view;
  final caregiver = DoseWidgetState.build(
    owner: 'caregiver-a',
    cache: null,
    operations: [],
    previous: {
      'patient_cache': {
        'date': doseWidgetDay(now),
        'patients': [
          {
            'key': 'contract-patient-key',
            'alias': 'patient',
            'schedules': snapshot['schedules'],
          },
        ],
      },
    },
    now: now,
    configuration: {'source': 'patients'},
  ).view;
  final pages = (own['pages'] as List).cast<Map>();
  final patients = (caregiver['patients'] as List).cast<Map>();
  expect(pages, isNotEmpty);
  expect(patients, isNotEmpty);
  return {
    ...own.keys,
    ...caregiver.keys,
    for (final entry in [...pages, ...patients]) ...entry.keys.cast<String>(),
  };
}

// Function Name: main
// Description:
// - Register text and state-shape checks for the contract between the Dart widget service and
//   the Kotlin widget provider and refresh scheduler.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  final provider = File(
    '$_kotlinDirectory/DoseWidgetProvider.kt',
  ).readAsStringSync();
  final scheduler = File(
    '$_kotlinDirectory/DoseWidgetRefreshScheduler.kt',
  ).readAsStringSync();
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final service = File(
    'lib/services/dose_home_widget_service.dart',
  ).readAsStringSync();

  // Function Name: test callback
  // Description:
  // - Verify that the provider class Dart addresses is the Kotlin class the manifest registers.
  //   The Kotlin package is the pinned widget's component identity and must not be renamed.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('Dart addresses the widget provider the manifest registers', () {
    final package = RegExp(
      r'^package ([\w.]+)$',
      multiLine: true,
    ).firstMatch(provider)?.group(1);
    expect(provider, contains('class DoseWidgetProvider : HomeWidgetProvider()'));
    expect('$package.DoseWidgetProvider', DoseHomeWidget.provider);
    expect(
      File('android/app/build.gradle.kts').readAsStringSync(),
      contains('namespace = "$package"'),
    );
    expect(manifest, contains('<receiver android:name=".DoseWidgetProvider"'));
    expect(manifest, contains('es.antonborri.home_widget.action.LAUNCH'));
  });

  // Function Name: test callback
  // Description:
  // - Verify that both sides use the same preference keys for the published state and for the
  //   journal of queued widget actions.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('Dart and Kotlin share the widget preference keys', () {
    expect(_stringConstant(provider, 'STATE'), DoseHomeWidget.stateKey);
    expect(_stringConstant(provider, 'JOURNAL'), DoseHomeWidget.journalKey);
    expect(DoseHomeWidget.stateKey, 'dose_widget_state');
    expect(DoseHomeWidget.journalKey, 'dose_widget_actions');
  });

  // Function Name: test callback
  // Description:
  // - Verify that the Kotlin scheduler enqueues the plugin's background worker under the
  //   plugin's work name and input key, with the refresh URI the Dart callback accepts.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('Kotlin schedules the refresh the Dart callback accepts', () {
    expect(_stringConstant(scheduler, 'WORK_NAME'), 'home_widget_background');
    expect(scheduler, contains('OneTimeWorkRequestBuilder<HomeWidgetBackgroundWorker>()'));
    final input = RegExp(
      r'putString\("([^"]+)", "([^"]+)"\)',
    ).firstMatch(scheduler);
    expect(input?.group(1), 'uri_data');
    final refresh = Uri.parse(input!.group(2)!);
    expect(refresh.toString(), 'medbuddy-widget://refresh');
    // The entry point lives in the composition layer; the service only registers the function it is given.
    final background = File(
      'lib/composition/dose_home_widget_background.dart',
    ).readAsStringSync();
    expect(
      background,
      contains(
        "uri?.scheme != '${refresh.scheme}' || uri?.host != '${refresh.host}'",
      ),
    );
    expect(background, contains("@pragma('vm:entry-point')"));
    expect(
      service,
      contains('HomeWidget.registerInteractivityCallback(callback)'),
    );
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains('DoseHomeWidget.initialize(doseHomeWidgetCallback)'),
    );
  });

  // Function Name: test callback
  // Description:
  // - Verify that every JSON key the Kotlin provider reads is produced by the Dart widget state,
  //   apart from the handled-token list the service adds and the keys Kotlin stores for itself.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('every JSON key Kotlin reads is published by Dart', () {
    final read = RegExp(
      r'\.(?:opt[A-Za-z]*|has|getJSON[A-Za-z]*)\("([a-z_]+)"',
    ).allMatches(provider).map((match) => match.group(1)!).toSet();
    expect(read.length, greaterThanOrEqualTo(24));
    expect(service, contains("'handled': handled"));
    final published = {..._publishedKeys(), 'handled'};
    expect(read.difference(published), _nativeOnlyKeys);
    for (final key in _nativeOnlyKeys) {
      expect(provider, contains('.put("$key"'), reason: key);
    }
  });
}
