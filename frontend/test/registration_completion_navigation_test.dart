import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medbuddy_frontend/boundaries/check_medication_detail_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_result_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_saved_medication_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_schedule_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/input_prescription_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manual_medication_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_registration_flow.dart';
import 'package:medbuddy_frontend/boundaries/pill_identification_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/identified_pill_save_request_entity.dart';
import 'package:medbuddy_frontend/entities/pill_identification_entity.dart';
import 'package:medbuddy_frontend/widgets/keep_words_text.dart';
import 'package:medbuddy_frontend/boundaries/medbuddy_bottom_navigation_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_caregiver_home_control.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/controls/manage_chat_list_control.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/prescription_local_ocr_service.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/views/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _completionKey = Key('prescription-save-completed-dialog');
const _medicationName = 'Navigation fixture';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    final font = Platform.environment['MEDBUDDY_TEST_FONT'];
    if (font == null) return;
    final bytes = ByteData.sublistView(await File(font).readAsBytes());
    for (final family in ['Roboto', 'Noto Sans KR', 'Arial', 'Ahem']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final origin in ['manual-home', 'manual-menu', 'pill']) {
    testWidgets('$origin hands review to shared results before any save', (
      tester,
    ) async {
      final harness = await _mount(tester);
      final home = tester.element(find.byType(HomeScreen));
      final entry = ManualMedicationEntry(
        medicationName: _medicationName,
        dosageAmount: '1',
        dosageUnit: '정',
        startDate: DateTime.now(),
        endDate: DateTime.now(),
        scheduleSlotKeys: const ['morning'],
      );
      if (origin == 'manual-home') {
        tester
            .widget<InputPrescriptionUI>(find.byType(InputPrescriptionUI))
            .onManualMedicationRequested!();
        await tester.pumpAndSettle();
      } else if (origin == 'manual-menu') {
        unawaited(openMedicationRegistration(home));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is KeepWordsText && widget.data == '직접 등록',
          ),
        );
        await tester.pumpAndSettle();
      } else {
        unawaited(openPillIdentification(home, harness.model));
        await tester.pumpAndSettle();
      }
      final accepted = origin.startsWith('manual')
          ? tester
                .widget<ManualMedicationEntryUI>(
                  find.byType(ManualMedicationEntryUI),
                )
                .onReviewRequested([entry])
          : tester
                .widget<PillIdentificationUI>(find.byType(PillIdentificationUI))
                .onReviewRequested([
                  IdentifiedPillSaveRequest(
                    candidate: const PillIdentificationCandidate(
                      itemSeq: 'fixture-item',
                      itemName: _medicationName,
                      manufacturer: 'fixture',
                      matchScore: 1,
                    ),
                    medicationSchedule: entry.toMedicationSchedule(),
                  ),
                ]);
      expect(accepted, isTrue);
      await tester.pumpAndSettle();
      expect(harness.rootRoute.isCurrent, isTrue);
      expect(harness.savedRows, isEmpty);
      expect(find.byType(CheckResultUI), findsOneWidget);
      expect(
        find.byType(ManualMedicationEntryUI, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(PillIdentificationUI, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(
          const Key('medication-registration-page'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        tester.widget<CheckResultUI>(find.byType(CheckResultUI)).source,
        origin.startsWith('manual')
            ? MedicationResultSource.manual
            : MedicationResultSource.pillPhoto,
      );
      await tester.tap(find.byKey(const Key('prescription-save-all')));
      await tester.pumpAndSettle();
      expect(harness.savedRows, hasLength(1));
      expect(find.byKey(_completionKey), findsOneWidget);
      harness.observer.events.clear();
      await tester.tap(find.byKey(const Key('prescription-save-open-pillbox')));
      expect(harness.observer.actions, ['pop', 'push']);
      await tester.pumpAndSettle();
      expect(find.byType(CheckSavedMedicationUI), findsOneWidget);
      expect(find.text(_medicationName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['ko', 'en']) {
    for (final individual in [false, true]) {
      testWidgets(
        '$language ${individual ? 'individual' : 'bulk'} save opens only the cabinet after the completion dialog',
        (tester) async {
          final harness = await _mount(tester, language: language);
          await harness.openCompletion(tester, individual: individual);
          final dialogRoute = harness.observer.events.last.route;
          expect(dialogRoute, isA<DialogRoute<void>>());
          harness.observer.events.clear();

          final cabinetButton = find.byKey(
            const Key('prescription-save-open-pillbox'),
          );
          expect(cabinetButton.hitTestable(), findsOneWidget);
          await tester.tap(cabinetButton);

          // Both operations must happen in the tap callback, without a frame
          // that routes through the registration menu or medication details.
          expect(harness.observer.actions, ['pop', 'push']);
          expect(harness.observer.events.first.route, same(dialogRoute));
          expect(
            harness.observer.events.first.previous,
            same(harness.rootRoute),
          );
          final cabinetRoute = harness.observer.events.last.route;
          expect(cabinetRoute, isA<MaterialPageRoute<void>>());
          expect(
            harness.observer.events.last.previous,
            same(harness.rootRoute),
          );
          expect(cabinetRoute.isCurrent, isTrue);
          expect(harness.rootRoute.isCurrent, isFalse);
          expect(
            harness.model.prescriptionFlowState,
            PrescriptionFlowState.idle,
          );

          await tester.pump();
          final underlyingHome = find.byType(
            InputPrescriptionUI,
            skipOffstage: false,
          );
          expect(underlyingHome, findsOneWidget);
          expect(
            ModalRoute.of(tester.element(underlyingHome)),
            same(harness.rootRoute),
          );
          expect(harness.rootRoute.isCurrent, isFalse);
          for (var frame = 0; frame < 30; frame++) {
            _expectNoIntermediateScreen();
            final cabinet = find.byType(
              CheckSavedMedicationUI,
              skipOffstage: false,
            );
            expect(cabinet, findsOneWidget);
            expect(ModalRoute.of(tester.element(cabinet)), same(cabinetRoute));
            expect(cabinetRoute.isCurrent, isTrue);
            expect(harness.observer.actions, ['pop', 'push']);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await tester.pumpAndSettle();
          expect(find.byKey(_completionKey), findsNothing);
          expect(find.byType(CheckSavedMedicationUI), findsOneWidget);
          expect(find.text(_medicationName), findsOneWidget);
          expect(find.byType(CheckResultUI, skipOffstage: false), findsNothing);
          expect(tester.takeException(), isNull);

          // Clearing analysis restores Home underneath the new route. It is
          // the back destination, not another pushed screen on the way in.
          await tester.tap(
            find.byKey(const ValueKey('savedMedicationCloseButton')),
          );
          await tester.pumpAndSettle();
          expect(harness.observer.actions, ['pop', 'push', 'pop']);
          expect(harness.observer.events.last.route, same(cabinetRoute));
          expect(harness.rootRoute.isCurrent, isTrue);
          _expectDestination(tester, MedBuddyDestination.home);
          expect(find.byType(InputPrescriptionUI), findsOneWidget);
          expect(find.byType(CheckSavedMedicationUI), findsNothing);
          expect(find.byType(CheckResultUI), findsNothing);
          _expectNoIntermediateScreen();
          expect(harness.savedRows, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final destination in [
    MedBuddyDestination.schedule,
    MedBuddyDestination.home,
  ]) {
    testWidgets(
      'save completion selects ${destination.name} in the existing shell without pushing a screen',
      (tester) async {
        final harness = await _mount(tester);
        if (destination == MedBuddyDestination.home) {
          await tester.tap(
            find.byKey(const ValueKey('bottomNavigation-schedule')),
          );
          await tester.pumpAndSettle();
          _expectDestination(tester, MedBuddyDestination.schedule);
        }
        await harness.openCompletion(tester);
        final dialogRoute = harness.observer.events.last.route;
        harness.observer.events.clear();
        await tester.tap(
          find.byKey(
            Key(
              destination == MedBuddyDestination.schedule
                  ? 'prescription-save-open-today'
                  : 'prescription-save-open-home',
            ),
          ),
        );
        expect(harness.observer.actions, ['pop']);
        expect(harness.observer.events.single.route, same(dialogRoute));
        expect(
          harness.observer.events.single.previous,
          same(harness.rootRoute),
        );
        await tester.pumpAndSettle();

        expect(harness.observer.actions, ['pop']);
        expect(harness.rootRoute.isCurrent, isTrue);
        expect(harness.model.prescriptionFlowState, PrescriptionFlowState.idle);
        _expectDestination(tester, destination);
        expect(find.byKey(_completionKey), findsNothing);
        expect(find.byType(CheckResultUI, skipOffstage: false), findsNothing);
        expect(
          find.byType(CheckSavedMedicationUI, skipOffstage: false),
          findsNothing,
        );
        if (destination == MedBuddyDestination.schedule) {
          expect(find.byType(CheckScheduleUI), findsOneWidget);
          expect(harness.model.todayMedicationScheduleList, hasLength(1));
        } else {
          expect(find.byType(InputPrescriptionUI), findsOneWidget);
          expect(find.byType(CheckScheduleUI), findsNothing);
        }
        _expectNoIntermediateScreen();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

void _expectNoIntermediateScreen() {
  expect(
    find.byKey(const Key('medication-registration-page'), skipOffstage: false),
    findsNothing,
  );
  for (final type in [
    CheckMedicationDetailUI,
    ManualMedicationEntryUI,
    PrescriptionAnalysisPreviewUI,
  ]) {
    expect(find.byType(type, skipOffstage: false), findsNothing);
  }
}

void _expectDestination(WidgetTester tester, MedBuddyDestination destination) {
  expect(
    tester
        .widget<MedBuddyBottomNavigationUI>(
          find.byType(MedBuddyBottomNavigationUI),
        )
        .selectedDestination,
    destination,
  );
}

Future<_Harness> _mount(WidgetTester tester, {String language = 'ko'}) async {
  final harness = _Harness(language);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(harness.model.inputPrescription.clearSelectedImage);
    harness.model.dispose();
    harness.links.dispose();
    harness.client.close();
  });
  await tester.pumpWidget(
    ChangeNotifierProvider<MedBuddyViewModel>.value(
      value: harness.model,
      child: MaterialApp(
        theme: MedBuddyTheme.light(),
        locale: Locale(language),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('ko'), Locale('en')],
        navigatorObservers: [harness.observer],
        home: HomeScreen(
          chatListFactory: (owner) => ManageChatList(
            userHash: owner,
            client: harness.client,
            linkControl: harness.links,
            isEnglish: language == 'en',
          ),
          caregiverHomeFactory: _CaregiverHome.new,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(harness.observer.actions, ['push']);
  harness.rootRoute = harness.observer.events.single.route;
  expect(tester.takeException(), isNull);
  return harness;
}

typedef _RouteEvent = ({
  String action,
  Route<dynamic> route,
  Route<dynamic>? previous,
});

class _RouteObserver extends NavigatorObserver {
  final events = <_RouteEvent>[];

  List<String> get actions => events.map((event) => event.action).toList();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add((action: 'push', route: route, previous: previousRoute));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add((action: 'pop', route: route, previous: previousRoute));
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    events.add((action: 'replace', route: newRoute!, previous: oldRoute));
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add((action: 'remove', route: route, previous: previousRoute));
  }
}

class _Harness {
  _Harness(String language) {
    client = MockClient(_respond);
    links = _Links(client);
    model = _Model(client, language);
  }

  late final MockClient client;
  late final _Links links;
  late final _Model model;
  late final Route<dynamic> rootRoute;
  final observer = _RouteObserver();
  final savedRows = <Map<String, dynamic>>[];
  final today = DateTime.now().toIso8601String().substring(0, 10);

  Future<void> openCompletion(
    WidgetTester tester, {
    bool individual = false,
  }) async {
    // Keep the real OCR/result/save state machine; replace only external input.
    await tester.runAsync(() async {
      await model.requestCapturedPrescriptionImage(
        XFile('registration-navigation-fixture.png'),
      );
    });
    expect(
      model.prescriptionFlowState,
      PrescriptionFlowState.analysisSucceeded,
    );
    model.showMedicationAnalysisResult();
    await tester.pumpAndSettle();
    expect(model.prescriptionFlowState, PrescriptionFlowState.resultReady);
    expect(find.byType(CheckResultUI), findsOneWidget);
    expect(observer.actions, ['push']);

    final save = individual
        ? find.byKey(const Key('result-medication-save-0'))
        : find.byKey(const Key('prescription-save-all'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(savedRows, hasLength(1));
    expect(model.completedMedicationSaveIndexes, {0});
    expect(find.byKey(_completionKey), findsOneWidget);
    expect(observer.actions, ['push', 'push']);
    expect(tester.takeException(), isNull);
  }

  Future<http.Response> _respond(http.Request request) async {
    final path = request.url.path;
    final Object body;
    if (path.endsWith('/analyze-prescription-text')) {
      body = {
        'prescription_date': today,
        'prescription_batch_id': 'navigation_fixture_0001',
        'medications': [
          {
            'drug_name': _medicationName,
            'dosage_per_time': '1',
            'daily_frequency': '1',
            'total_days': '7',
          },
        ],
      };
    } else if (path.contains('/catalog/')) {
      body = {
        'success': true,
        'data': {
          'item_seq': request.url.pathSegments.last,
          'item_name': _medicationName,
        },
      };
    } else if (path.endsWith('/identify')) {
      body = {
        'success': true,
        'data': [
          {
            'item_name': _medicationName,
            'efficacy': '',
            'usage_method': '',
            'warning': '',
          },
        ],
      };
    } else if (path.endsWith('/change-radar')) {
      body = {'has_previous_prescription': false};
    } else if (path.endsWith('/save')) {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['patient_hash'], model.patientHash);
      savedRows.add({...payload, 'id': savedRows.length + 1});
      body = {'success': true, 'id': savedRows.length};
    } else if (path.endsWith('/list') || path.endsWith('/schedule/today')) {
      expect(request.url.queryParameters['patient_hash'], model.patientHash);
      body = {'success': true, 'data': savedRows};
    } else {
      throw StateError('Unexpected navigation fixture request: $path');
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

class _Model extends MedBuddyViewModel {
  _Model(http.Client client, String language)
    : setting = UserSetting(language: language, homeScheduleSource: 'self'),
      super(
        patientHash: 'registration-navigation-patient',
        apiClient: client,
        inputPrescription: InputPrescription(
          client: client,
          localOcrBoundary: _LocalOcr(),
        ),
      );

  final UserSetting setting;

  @override
  UserSetting get userSetting => setting;
}

class _LocalOcr implements PrescriptionLocalOcrBoundary {
  @override
  Future<LocalPrescriptionOcrResult> recognizeAndMask(String imagePath) async =>
      const LocalPrescriptionOcrResult(
        maskedText: 'Synthetic prescription navigation fixture',
        regions: [],
      );
}

class _Links extends LinkPatientCaregiver {
  _Links(http.Client client) : super(client: client);

  @override
  Future<List<PatientCaregiverLink>> requestLinkScreen() async => [];
}

class _CaregiverHome extends CheckCaregiverHome {
  _CaregiverHome(String owner) : super(userHash: owner);

  @override
  Future<void> refresh() async {}
}
