import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/boundaries/caregiver_home_summary_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_caregiver_medication_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_history_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_home_control.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_medication_control.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/controls/manage_chat_list_control.dart';
import 'package:medbuddy_frontend/controls/medication_history_control.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_feature_updates.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/views/home_screen.dart';
import 'package:medbuddy_frontend/widgets/keep_words_text.dart';
import 'package:medbuddy_frontend/widgets/medbuddy_page_header.dart';
import 'package:medbuddy_frontend/widgets/medication_schedule_header.dart';

import 'medication_history_fixtures.dart';
import 'support/fake_as_needed_pending_store.dart';

// Role: Supplies an inert transport. Parameters: request. Returns: empty JSON.
Future<http.Response> _empty(http.Request request) async =>
    http.Response('{}', 200);

class _Model extends MedBuddyViewModel {
  UserSetting setting;
  _Model({
    String owner = 'owner',
    String source = 'patients',
    String language = 'en',
  }) : setting = UserSetting(homeScheduleSource: source, language: language),
       super(patientHash: owner, apiClient: MockClient(_empty));

  @override
  UserSetting get userSetting => setting;

  // Role: Publishes a source change. Parameters: source. Returns: none.
  void source(String source) {
    setting = setting.copyWith(homeScheduleSource: source);
    updatesFor(MedBuddyFeature.userSetting).markChanged();
  }
}

class _Links extends LinkPatientCaregiver {
  List<PatientCaregiverLink> result = [];
  bool fail = false;
  Completer<List<PatientCaregiverLink>>? pending;
  _Links() : super(client: MockClient(_empty));

  // Role: Supplies current links or a delayed/error result. Parameters: none. Returns: links.
  @override
  Future<List<PatientCaregiverLink>> requestLinkScreen() async {
    if (pending != null) return pending!.future;
    if (fail) throw StateError('offline');
    return result;
  }
}

class _Home extends CheckCaregiverHome {
  _Home(String owner) : super(userHash: owner);
  // Role: Avoids unrelated home reads. Parameters: none. Returns: completed future.
  @override
  Future<void> refresh() async {}
}

class _Schedule extends CheckCaregiverMedication {
  final _Harness harness;
  _Schedule(String owner, this.harness)
    : super(caregiverHash: owner, client: MockClient(_empty));

  // Role: Records and optionally delays a patient schedule. Parameters: patientHash. Returns: scoped schedule.
  @override
  Future<CaregiverMedicationInfo> requestPatientMedicationInfo({
    required String patientHash,
  }) async {
    harness.scheduleReads.add((caregiverHash, patientHash));
    await harness.pendingSchedule?.future;
    return (
      caregiverHash: caregiverHash,
      patientHash: patientHash,
      savedMedications: <MedicationDetail>[],
      todayMedicationScheduleList: [
        MedicationSchedule(
          medicationID: '1',
          medicationName: '$patientHash schedule',
          dosage: '1',
          intakeTime: '1',
          slotStatuses: const {'morning': false},
        ),
      ],
    );
  }
}

// Role: Creates a relationship fixture. Parameters: id, owner, patient, alias, active. Returns: link.
PatientCaregiverLink _link(
  int id, {
  String owner = 'owner',
  String? patient,
  String? alias,
  bool active = true,
}) => PatientCaregiverLink(
  linkId: id,
  patientHash: patient ?? 'patient-$id',
  caregiverHash: owner,
  patientAlias: alias ?? 'Patient $id',
  linkStatus: active,
);

class _Harness {
  _Model model;
  final links = _Links();
  final chats = <String, ManageChatList>{};
  final historyControls = <MedicationHistoryControl>[];
  final historyReads = <http.Request>[];
  final scheduleReads = <(String, String)>[];
  final pendingHistory = <String, Completer<void>>{};
  Completer<void>? pendingSchedule;
  _Harness(this.model);

  // Role: Responds to history reads, preserving requested dates. Parameters: request. Returns: scoped records.
  Future<http.Response> historyResponse(http.Request request) async {
    expect(request.method, 'GET');
    historyReads.add(request);
    final patient = request.url.queryParameters['patient_hash']!;
    await pendingHistory[patient]?.future;
    return historyTestResponse(
      historyTestBody(
        start: request.url.queryParameters['start_date']!,
        end: request.url.queryParameters['end_date']!,
        items: [historyTestEntry(name: '$patient history', date: '2026-10-17')],
      ),
    );
  }

  // Role: Mounts the real navigation shell with controlled queries. Parameters: tester, width, scale. Returns: first frame.
  Future<void> pump(
    WidgetTester tester, {
    double width = 390,
    double height = 850,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: model,
        child: MaterialApp(
          theme: MedBuddyTheme.light(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en'), Locale('ko')],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: HomeScreen(
            chatListFactory: (owner) => chats[owner] = ManageChatList(
              userHash: owner,
              linkControl: links,
              client: MockClient(_empty),
              isEnglish: true,
            ),
            caregiverHomeFactory: _Home.new,
            caregiverMedicationFactory: (owner) => _Schedule(owner, this),
            historyFactory:
                ({
                  required patientHash,
                  required readOnly,
                  required isScopeCurrent,
                }) {
                  final control = MedicationHistoryControl(
                    patientHash: patientHash,
                    readOnly: readOnly,
                    isScopeCurrent: isScopeCurrent,
                    client: MockClient(historyResponse),
                    now: () => historyTestNow,
                    sessionKeyProvider: () => model.patientHash,
                    pendingStore: FakeAsNeededPendingStore(),
                  );
                  historyControls.add(control);
                  return control;
                },
          ),
        ),
      ),
    );
  }

  // Role: Publishes link changes. Parameters: tester. Returns: settled UI.
  Future<void> refresh(WidgetTester tester) async {
    await chats[model.patientHash]!.refresh();
    await tester.pumpAndSettle();
  }
}

// Role: Selects a navigation tab. Parameters: tester, destination, settle. Returns: rendered tab.
Future<void> _tab(
  WidgetTester tester,
  String destination, {
  bool settle = true,
}) async {
  await tester.tap(find.byKey(ValueKey('bottomNavigation-$destination')));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

// Role: Reads the visible history configuration. Parameters: tester. Returns: history widget.
MedicationHistoryUI _history(WidgetTester tester) =>
    tester.widget(find.byType(MedicationHistoryUI));

// Role: Reads the visible linked schedule configuration. Parameters: tester. Returns: schedule widget.
CheckCaregiverMedicationUI _schedule(WidgetTester tester) =>
    tester.widget(find.byType(CheckCaregiverMedicationUI));

// Role: Registers shared-patient navigation and invalidation regressions. Parameters: none. Returns: none.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Role: Builds a harness and registers cleanup. Parameters: tester, source, language. Returns: harness.
  _Harness harness(
    WidgetTester tester, {
    String source = 'patients',
    String language = 'en',
  }) {
    final h = _Harness(_Model(source: source, language: language));
    addTearDown(() {
      h.model.dispose();
      h.links.dispose();
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return h;
  }

  testWidgets(
    'self source retains editable history and own schedule despite links',
    (tester) async {
      final h = harness(tester, source: 'self');
      h.links.result = [_link(1)];
      await h.pump(tester);
      await tester.pumpAndSettle();
      await _tab(tester, 'medicationHistory');
      final history = _history(tester);
      final state = tester.state(find.byType(MedicationHistoryUI));
      expect(history.patientHash, 'owner');
      expect(history.readOnly, isFalse);
      expect(history.onChanged, isNotNull);
      expect(history.recordChanges, same(h.model.savedDoseRecords));
      await _tab(tester, 'schedule');
      expect(find.byType(CheckScheduleUI), findsOneWidget);
      expect(find.byType(CheckCaregiverMedicationUI), findsNothing);
      await _tab(tester, 'medicationHistory');
      expect(tester.state(find.byType(MedicationHistoryUI)), same(state));
      expect(h.scheduleReads, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'home carousel, schedule and history share the selected patient',
    (tester) async {
      final h = harness(tester);
      h.links.result = [
        _link(1),
        _link(2),
        _link(3, active: false),
        _link(4, owner: 'other'),
        _link(5, owner: 'caregiver', patient: 'owner'),
      ];
      await h.pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('caregiver-patient-next')));
      await tester.pumpAndSettle();
      await _tab(tester, 'schedule');
      expect(_schedule(tester).patientHash, 'patient-2');
      expect(_schedule(tester).showBackButton, isFalse);
      final header = tester.widget<MedicationScheduleHeader>(
        find.byType(MedicationScheduleHeader),
      );
      expect(header.title, "Today's Medication Schedule");
      expect(header.subtitle, isNull);
      expect(h.scheduleReads.last, ('owner', 'patient-2'));
      expect(
        tester
            .widget<ColoredBox>(
              find.byKey(const Key('schedule-patient-selector-surface')),
            )
            .color,
        MedBuddyColors.pageBackground,
      );
      final patientName = tester.widget<KeepWordsText>(
        find.byKey(const Key('schedule-patient-name')),
      );
      expect(patientName.style?.color, MedBuddyColors.textStrong);
      expect(patientName.style?.fontWeight, FontWeight.w700);
      expect(patientName.style?.fontSize, 17);
      expect(
        patientName.style,
        MedBuddyPageHeader.titleStyle.copyWith(
          color: MedBuddyColors.textStrong,
          fontSize: 17,
        ),
      );
      await tester.tap(find.byKey(const Key('caregiver-schedule-history')));
      await tester.pumpAndSettle();
      expect(_history(tester).patientHash, 'patient-2');
      expect(_history(tester).readOnly, isTrue);
      expect(_history(tester).onChanged, isNull);
      expect(_history(tester).recordChanges, isNull);
      expect(find.text('Patient records · Read only'), findsOneWidget);
      await tester.tap(find.byKey(const Key('history-patient-previous')));
      await tester.pumpAndSettle();
      expect(_history(tester).patientHash, 'patient-1');
      await _tab(tester, 'home');
      expect(
        tester
            .widget<CaregiverHomeSummaryUI>(find.byType(CaregiverHomeSummaryUI))
            .selectedPatient!
            .patientHash,
        'patient-1',
      );
      await _tab(tester, 'schedule');
      expect(_schedule(tester).patientHash, 'patient-1');
      await tester.tap(find.byKey(const Key('schedule-patient-next')));
      await tester.pumpAndSettle();
      await _tab(tester, 'medicationHistory');
      expect(_history(tester).patientHash, 'patient-2');
      expect(
        h.historyReads.every(
          (r) => r.url.queryParameters['patient_hash'] != 'owner',
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'patient selection survives reordering and safely falls back after unlink',
    (tester) async {
      final h = harness(tester);
      h.links.result = [_link(1), _link(2)];
      await h.pump(tester);
      await tester.pumpAndSettle();
      await _tab(tester, 'medicationHistory');
      await tester.tap(find.byKey(const Key('history-patient-next')));
      await tester.pumpAndSettle();
      final old = _history(tester).control!;
      h.links.result = [_link(1, alias: 'Zed'), _link(2, alias: 'Amy')];
      await h.refresh(tester);
      expect(_history(tester).control, same(old));
      expect(find.text('Amy'), findsOneWidget);
      h.links.result = [_link(1)];
      await h.refresh(tester);
      expect(_history(tester).patientHash, 'patient-1');
      expect(old.snapshot, isNull);
      expect(
        old.ensureSession,
        throwsA(isA<MedicationHistorySessionChanged>()),
      );
      await _tab(tester, 'schedule');
      expect(_schedule(tester).patientHash, 'patient-1');
      h.links.result = [];
      await h.refresh(tester);
      expect(find.byKey(const Key('schedule-link-status')), findsOneWidget);
      expect(find.byType(CheckScheduleUI, skipOffstage: false), findsNothing);
      expect(
        find.byType(CheckCaregiverMedicationUI, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(MedicationHistoryUI, skipOffstage: false),
        findsNothing,
      );
      await _tab(tester, 'medicationHistory');
      expect(find.text('No linked patients.'), findsOneWidget);
      h.links.result = [_link(2)];
      await h.refresh(tester);
      expect(_history(tester).patientHash, 'patient-2');
      expect(_history(tester).control, isNot(same(old)));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'loading and failed links never expose self history or schedule',
    (tester) async {
      final h = harness(tester);
      final pending = h.links.pending = Completer<List<PatientCaregiverLink>>();
      await h.pump(tester);
      await _tab(tester, 'medicationHistory', settle: false);
      expect(find.text('Loading linked patients...'), findsOneWidget);
      expect(h.historyReads, isEmpty);
      await _tab(tester, 'schedule', settle: false);
      expect(find.byType(CheckScheduleUI), findsNothing);
      h.links.pending = null;
      h.links.fail = true;
      pending.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load linked patients.'), findsOneWidget);
      h.links.fail = false;
      h.links.result = [_link(1)];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(_schedule(tester).patientHash, 'patient-1');
      h.links.fail = true;
      await h.refresh(tester);
      expect(find.byType(CheckCaregiverMedicationUI), findsNothing);
      await _tab(tester, 'medicationHistory');
      expect(find.byType(MedicationHistoryUI), findsNothing);
      expect(
        h.historyReads.every(
          (r) => r.url.queryParameters['patient_hash'] != 'owner',
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final source in ['self', 'patients']) {
    testWidgets(
      'schedule and history feature search follow $source and shared selection',
      (tester) async {
        final h = harness(tester, source: source);
        h.links.result = [_link(1), _link(2)];
        await h.pump(tester);
        await tester.pumpAndSettle();
        if (source == 'patients') {
          await tester.tap(find.byKey(const Key('caregiver-patient-next')));
          await tester.pumpAndSettle();
        }
        for (final (feature, query) in [
          ('schedule', '오늘 먹을 약'),
          ('medicationHistory', '복약 기록'),
        ]) {
          await _tab(tester, 'home');
          await tester.tap(
            find.byKey(const ValueKey('homeFeatureSearchButton')),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('featureSearchInput')),
            query,
          );
          await tester.pump();
          await tester.tap(find.byKey(Key('feature-$feature')));
          await tester.pumpAndSettle();
          if (feature == 'schedule') {
            if (source == 'patients') {
              expect(_schedule(tester).patientHash, 'patient-2');
            } else {
              expect(find.byType(CheckScheduleUI), findsOneWidget);
            }
          } else {
            expect(
              _history(tester).patientHash,
              source == 'patients' ? 'patient-2' : 'owner',
            );
            expect(_history(tester).readOnly, source == 'patients');
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('self response is rejected when switching to empty patient scope', (
    tester,
  ) async {
    final h = harness(tester, source: 'self');
    final pending = h.pendingHistory['owner'] = Completer<void>();
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _tab(tester, 'medicationHistory', settle: false);
    final old = _history(tester).control!;
    // The access guard must reject even before the next build disposes the tab.
    h.model.source('patients');
    expect(old.ensureSession, throwsA(isA<MedicationHistorySessionChanged>()));
    pending.complete();
    await tester.pumpAndSettle();
    expect(old.snapshot, isNull);
    expect(find.byType(MedicationHistoryUI), findsNothing);
    await _tab(tester, 'schedule');
    expect(find.byType(CheckScheduleUI), findsNothing);
    expect(find.text('No linked patients.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'replacement session for the same account resets both patient views',
    (tester) async {
      final h = harness(tester);
      h.links.result = [_link(1)];
      await h.pump(tester);
      await tester.pumpAndSettle();
      await _tab(tester, 'schedule');
      final oldSchedule = tester.state(find.byType(CheckCaregiverMedicationUI));
      await _tab(tester, 'medicationHistory');
      final old = _history(tester).control!;
      final previous = h.model;
      h.model = _Model();
      addTearDown(previous.dispose);
      await h.pump(tester);
      await tester.pumpAndSettle();
      expect(old.snapshot, isNull);
      expect(_history(tester).control, isNot(same(old)));
      expect(
        old.ensureSession,
        throwsA(isA<MedicationHistorySessionChanged>()),
      );
      await _tab(tester, 'schedule');
      expect(
        tester.state(find.byType(CheckCaregiverMedicationUI)),
        isNot(same(oldSchedule)),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final change in ['source', 'account', 'unlink']) {
    testWidgets('$change rejects late patient history and schedule responses', (
      tester,
    ) async {
      final h = harness(tester);
      h.links.result = [_link(1)];
      final pending = h.pendingHistory['patient-1'] = Completer<void>();
      final schedulePending = h.pendingSchedule = Completer<void>();
      await h.pump(tester);
      await tester.pumpAndSettle();
      await _tab(tester, 'medicationHistory', settle: false);
      await tester.pump();
      final old = _history(tester).control!;
      await _tab(tester, 'schedule', settle: false);
      await tester.pump();
      final oldSchedule = _schedule(tester);
      if (change == 'source') {
        h.model.source('self');
      } else if (change == 'account') {
        final previous = h.model;
        h.model = _Model(owner: 'other');
        addTearDown(previous.dispose);
        await h.pump(tester);
      } else {
        h.links.result = [];
        await h.chats['owner']!.refresh();
      }
      await tester.pump();
      pending.complete();
      schedulePending.complete();
      h.pendingSchedule = null;
      await tester.pumpAndSettle();
      expect(old.snapshot, isNull);
      expect(
        old.ensureSession,
        throwsA(isA<MedicationHistorySessionChanged>()),
      );
      expect(oldSchedule.isScopeCurrent!(), isFalse);
      expect(find.text('patient-1 schedule'), findsNothing);
      if (change == 'source') {
        expect(find.byType(CheckScheduleUI), findsOneWidget);
        await _tab(tester, 'medicationHistory');
        expect(_history(tester).patientHash, 'owner');
        expect(_history(tester).readOnly, isFalse);
        h.model.source('patients');
        await tester.pumpAndSettle();
        expect(_history(tester).patientHash, 'patient-1');
        expect(_history(tester).control, isNot(same(old)));
        await _tab(tester, 'schedule');
        expect(_schedule(tester).patientHash, 'patient-1');
      } else {
        expect(find.byKey(const Key('schedule-link-status')), findsOneWidget);
        await _tab(tester, 'medicationHistory');
        expect(find.byType(MedicationHistoryUI), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('hidden linked schedule stops polling and resumes on selection', (
    tester,
  ) async {
    final h = harness(tester);
    h.links.result = [_link(1)];
    await h.pump(tester);
    await tester.pumpAndSettle();
    await _tab(tester, 'schedule');
    await _tab(tester, 'medicationHistory');
    final reads = h.scheduleReads.length;
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(h.scheduleReads.length, reads);
    await _tab(tester, 'schedule');
    expect(h.scheduleReads.length, greaterThan(reads));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in ['en', 'ko']) {
    testWidgets('patient selectors fit narrow large-text $language screens', (
      tester,
    ) async {
      final h = harness(tester, language: language);
      h.links.result = [
        _link(1, alias: 'A very long patient display name'),
        _link(2),
      ];
      await h.pump(tester, width: 320, height: 640, scale: 2);
      await tester.pumpAndSettle();
      await _tab(tester, 'medicationHistory');
      expect(tester.takeException(), isNull);
      await _tab(tester, 'schedule');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
