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
String? _stringConstant(String source, String name) =>
    RegExp('const val $name = "([^"]*)"').firstMatch(source)?.group(1);

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
    expect(
      provider,
      contains('class DoseWidgetProvider : HomeWidgetProvider()'),
    );
    expect('$package.DoseWidgetProvider', DoseHomeWidget.provider);
    expect(
      File('android/app/build.gradle.kts').readAsStringSync(),
      contains('namespace = "$package"'),
    );
    expect(manifest, contains('<receiver android:name=".DoseWidgetProvider"'));
    expect(manifest, contains('es.antonborri.home_widget.action.LAUNCH'));
  });

  // Function Name: test callback
  // Description: Keeps the default launcher identity and registers the larger size with the shared receiver logic.
  // Parameters: None. Returns: No value; mismatched metadata or duplicate action paths fail the test.
  test('4x3 is a separate launcher option with shared secure actions', () {
    final large = File(
      '$_kotlinDirectory/DoseWidgetLargeProvider.kt',
    ).readAsStringSync();
    expect(
      large,
      contains('class DoseWidgetLargeProvider : DoseWidgetProvider()'),
    );
    expect(
      DoseHomeWidget.expandedProvider,
      'com.example.medbuddy_frontend.DoseWidgetLargeProvider',
    );
    expect(
      manifest,
      contains(
        '<receiver android:name=".DoseWidgetLargeProvider" android:exported="false"',
      ),
    );
    for (final (file, height, minHeight, initial, preview) in [
      (
        'dose_home_widget_info',
        1,
        48,
        'dose_home_widget_row',
        'dose_home_widget_preview',
      ),
      (
        'dose_home_widget_large_info',
        3,
        180,
        'dose_home_widget',
        'dose_home_widget_expanded_preview',
      ),
    ]) {
      final xml = File(
        'android/app/src/main/res/xml/$file.xml',
      ).readAsStringSync();
      expect(xml, contains('android:targetCellWidth="4"'));
      expect(xml, contains('android:targetCellHeight="$height"'));
      expect(xml, contains('android:initialLayout="@layout/$initial"'));
      expect(xml, contains('android:previewLayout="@layout/$preview"'));
      expect(xml, contains('android:minHeight="${minHeight}dp"'));
      expect(xml, contains('android:minResizeHeight="48dp"'));
      expect(xml, contains('android:resizeMode="horizontal|vertical"'));
      expect(manifest, contains('android:resource="@xml/$file"'));
    }
    expect(
      provider,
      contains('ComponentName(context, DoseWidgetLargeProvider::class.java)'),
    );
    expect(provider, contains('val ids = widgetIds(context)'));
    expect(provider, contains('if (id !in widgetIds(context)) return'));
    expect(
      provider,
      contains('if (state.optString("source") == "patients") return'),
    );
    expect(
      provider,
      contains(
        'it.optString("token") == token && it.optString("action") == kind',
      ),
    );
    expect(
      provider,
      contains('System.currentTimeMillis() >= state.optLong("expires")'),
    );
    expect(provider, contains('if (queue.length() != 0) return'));
    expect(provider, contains('PendingIntent.FLAG_IMMUTABLE'));
    expect(
      provider,
      contains('Intent(context, DoseWidgetProvider::class.java)'),
    );
  });

  // Function Name: test callback
  // Description: Keeps both launcher sizes on the original responsive rendering path.
  // Parameters: None. Returns: No value; a size-specific rendering branch fails the test.
  test('4x1 and 4x3 share the existing responsive layouts', () {
    final layout = File(
      '$_kotlinDirectory/DoseWidgetLayout.kt',
    ).readAsStringSync();
    expect(
      provider,
      contains(
        'build(R.layout.dose_home_widget), build(R.layout.dose_home_widget_row)',
      ),
    );
    expect(provider, isNot(contains('getAppWidgetInfo(id)')));
    expect(provider, isNot(contains('R.layout.dose_home_widget_large')));
    expect(provider, isNot(contains('R.id.widget_overview')));
    expect(provider, isNot(contains('R.id.widget_slot_')));
    expect(layout, isNot(contains('overview')));
    expect(
      layout,
      contains('listOf(48, 60, ROW_LIMIT, 180, 230, 300, 340, 420)'),
    );
    for (final name in [
      'dose_home_widget_large',
      'dose_home_widget_large_preview',
      'dose_home_widget_overview',
    ]) {
      expect(
        File('android/app/src/main/res/layout/$name.xml').existsSync(),
        isFalse,
      );
    }
  });

  test(
    'widget picker previews use placeholders instead of live date or dose times',
    () {
      final preview = File(
        '$_kotlinDirectory/DoseWidgetPreview.kt',
      ).readAsStringSync();
      expect(preview, contains('"20XX.XX.XX"'));
      expect(preview, contains('"아침 --:--", "Morning --:--"'));
      expect(preview, isNot(contains('SimpleDateFormat')));
      expect(preview, isNot(contains('Date()')));
      expect(preview, isNot(contains('08:00')));
      expect(preview, isNot(contains('getSharedPreferences')));
    },
  );

  test('compact arrows use the shared scoped first and last slot actions', () {
    final row = File(
      'android/app/src/main/res/layout/dose_home_widget_row.xml',
    ).readAsStringSync();
    final ids = [
      'widget_previous',
      'widget_tiny_heading',
      'widget_tiny_status',
      'widget_next',
      'widget_take',
    ];
    final positions = ids
        .map((id) => row.indexOf('android:id="@+id/$id"'))
        .toList();
    expect(positions.every((position) => position >= 0), isTrue);
    expect(positions, orderedEquals([...positions]..sort()));
    final arrows = provider.substring(
      provider.indexOf(
        'for ((button, targetIndex) in listOf(R.id.widget_previous',
      ),
      provider.indexOf('views.setTextViewText(R.id.widget_take, when'),
    );
    for (final contract in [
      'R.id.widget_previous to index - 1, R.id.widget_next to index + 1',
      'val target = pages.getOrNull(targetIndex)',
      'layout == R.layout.dose_home_widget_row && pages.size <= 1',
      'View.GONE else if (target != null) View.VISIBLE else View.INVISIBLE',
      'views.setBoolean(button, "setEnabled", !pending && target != null)',
      'pageAction(context, id,',
      'target.optString("slot"), state.optString("navigation_key"))',
    ]) {
      expect(arrows, contains(contract));
    }
    expect(arrows, isNot(contains('optString("token")')));
    expect(provider, contains('broadcast(context, "page",'));
    expect(
      provider,
      contains(
        'listOf("widget" to id.toString(), "slot" to slot, "context" to key)',
      ),
    );
    expect(
      provider,
      contains(
        'selection.optString("context") == state.optString("navigation_key")',
      ),
    );
    expect(
      provider,
      contains(
        'pages.indexOfFirst { it.optString("slot") == selection.optString("slot") }',
      ),
    );
    expect(
      provider,
      contains(
        'if (selected >= 0) selected else if (next >= 0) next else pages.lastIndex',
      ),
    );
    expect(
      provider,
      contains(
        'action(context, page.optString("action"), page.optString("token"), id)',
      ),
    );
  });

  test(
    'shared page receiver keeps queue, date, account and patient scope guards',
    () {
      final receiver = provider.substring(
        provider.indexOf('if (kind == "page")'),
        provider.indexOf('if (kind != "refresh")'),
      );
      for (final contract in [
        'patientState(json(data.getString(STATE, "{}")), data, id)',
        'id !in ids || key != state.optString("navigation_key")',
        'System.currentTimeMillis() >= state.optLong("expires")',
        'pages(state).none { it.optString("slot") == slot }',
        'queue(data).length() > 0) return',
        'putString(pageKey(id), JSONObject()',
        '.put("context", key).put("slot", slot)',
      ]) {
        expect(receiver, contains(contract));
      }
      expect(receiver, isNot(contains('putString(JOURNAL')));
      expect(receiver, isNot(contains('wake(context')));
      expect(
        provider,
        contains('if (state.optString("source") == "patients") return'),
      );
      expect(
        provider,
        contains('if (known && !expired) pages(state) else emptyList()'),
      );
      expect(
        provider,
        contains(
          'root.optString("navigation_key") + ":" + patient.optString("patient_key")',
        ),
      );
    },
  );

  test(
    'native date fallback uses the same full date in Korean and English',
    () {
      expect(provider, contains('SimpleDateFormat("yyyy.MM.dd (EEE)",'));
      expect(
        provider,
        contains('if (english) Locale.ENGLISH else Locale.KOREAN'),
      );
      expect(
        provider,
        contains('state.optInt("utc_offset_minutes", 540) * 60000'),
      );
      expect(
        provider,
        contains(
          'state.optString("date_label") else dateFormat.format(Date())',
        ),
      );
    },
  );

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
    expect(
      scheduler,
      contains('OneTimeWorkRequestBuilder<HomeWidgetBackgroundWorker>()'),
    );
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
