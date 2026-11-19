// File Name: registration.dart
// Role: Render actual registration widgets with synthetic review and save data.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/check_result_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_schedule_review_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_status_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/analyzed_medication_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_match_review_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_change_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/recognized_text_region_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/medication_review_image_gallery.dart';

final root = Platform.environment['GUIDE_WORKSPACE']!;
final out = Platform.environment['GUIDE_CAPTURE_OUTPUT']!;
const capture = Key('visual-capture');
final schedules = [
  MedicationSchedule(medicationName: '소론도정(프레드니솔론)',
    prescriptionDate: DateTime(2026, 11, 16), dosage: '1정', intakeTime: '2회',
    medicationTime: 7, scheduleSlotKeys: ['morning', 'evening']),
  MedicationSchedule(medicationName: '타이레놀정500밀리그램(아세트아미노펜)',
    prescriptionDate: DateTime(2026, 11, 16), dosage: '1정', intakeTime: '3회',
    medicationTime: 5, scheduleSlotKeys: ['morning', 'lunch', 'evening']),
];
// Function Name: noop
// Description: Ignore navigation callbacks without entering a real account.
// Parameters: None.
// Returns: void; no side effects.
void noop() {}

// Function Name: app
// Description: Wrap a product page in a Korean test theme and fixed safe area.
// Parameters: page is the product widget to render.
// Returns: Widget with a keyed capture boundary and no debug banner.
Widget app(Widget page) => RepaintBoundary(
  key: capture,
  child: MaterialApp(
    key: UniqueKey(),
    debugShowCheckedModeBanner: false,
    theme: MedBuddyTheme.light().copyWith(
      textTheme: MedBuddyTheme.light().textTheme.apply(fontFamily: 'Noto Sans KR'),
      primaryTextTheme: MedBuddyTheme.light().primaryTextTheme.apply(fontFamily: 'Noto Sans KR'),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: const EdgeInsets.only(top: 28, bottom: 24),
        viewPadding: const EdgeInsets.only(top: 28, bottom: 24),
      ),
      child: child!,
    ),
    home: page,
  ),
);

// Function Name: snapshot
// Description: Save the rendered boundary at 2x and reject widget errors.
// Parameters: tester drives rendering; name is the output PNG stem.
// Returns: Future<void>; writes the snapshot or fails on rendering/file errors.
Future<void> snapshot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(capture));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  expect(tester.takeException(), isNull);
}

// Function Name: main
// Description: Register isolated registration captures using synthetic callbacks.
// Parameters: None.
// Returns: void; configures test fonts and registers the visual fixture test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'Roboto': 'NotoSansCJK-Regular.ttc',
      'Noto Sans KR': 'NotoSansCJK-Regular.ttc',
      'Ahem': 'NotoSansCJK-Regular.ttc',
      'Arial': 'NotoSansCJK-Regular.ttc',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(Future.value(ByteData.sublistView(File(Platform.environment['GUIDE_CAPTURE_FONT']!).readAsBytesSync())));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons');
    icons.addFont(Future.value(ByteData.sublistView(File('${Platform.environment['GUIDE_FLUTTER_SDK']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
    await icons.load();
  });
  setUp(() {});

  // Function Name: registration presentation visual verification
  // Description: Render prescription/manual/pill review, result and save dialogs.
  // Parameters: tester supplies the isolated widget test environment.
  // Returns: Future<void>; writes snapshots and fails on unexpected widget errors.
  testWidgets('registration presentation visual verification', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final photoBytes = [for (var i = 1; i <= 2; i++)
      File('$root/work/partial-pill-reference-$i.jpg').readAsBytesSync()];
    await tester.pumpWidget(app(const Scaffold(body: Text('Loading'))));
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold));
      for (final bytes in photoBytes) {
        await precacheImage(MemoryImage(bytes), context).timeout(const Duration(seconds: 5));
      }
      await precacheImage(FileImage(File('$root/work/full-audit-20261010/test-prescription.png')), context).timeout(const Duration(seconds: 5));
    });
    final photos = [for (var i = 1; i <= 2; i++) MedicationReviewPhoto(
      title: '사진 예시 알약 $i',
      imageBuilder: (context) => Image.memory(
        photoBytes[i-1], fit: BoxFit.contain),
    )];
    await tester.pumpWidget(app(Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showMedicationScheduleReview(
        context: context, initialSchedules: [for (var i = 0; i < schedules.length; i++)
          schedules[i].copyWith(medicationName: '사진 예시 알약 ${i + 1}')], userSetting: const UserSetting(), photos: photos,
      ), child: const Text('open')),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await snapshot(tester, 'pill-review');
    await tester.tap(find.byKey(const Key('schedule-review-edit-0')));
    await tester.pumpAndSettle();
    await snapshot(tester, 'pill-review-edit');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medication-review-gallery-photo-0')));
    await tester.pumpAndSettle();
    await snapshot(tester, 'pill-photo-dialog');
    await tester.tapAt(const Offset(5, 80));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medication-review-gallery-preview')), findsOneWidget);

    await tester.pumpWidget(app(PrescriptionAnalysisPreviewUI(
      medicationScheduleList: schedules,
      previewImagePath: '$root/work/full-audit-20261010/test-prescription.png',
      recognizedTextRegions: const [RecognizedTextRegion(category: 'medication_row', text: '소론도정', box2d: [420, 40, 470, 350])],
      userSetting: const UserSetting(), onBackRequested: noop, onAnalysisRequested: noop,
      onMedicationScheduleChanged: (_, _) {}, onMedicationScheduleAdded: (_) {},
      isMedicationLookupReview: true, verifiedScheduleIndexes: const {0},
      onVerifiedOnlyContinueRequested: noop,
    )));
    await tester.pumpAndSettle();
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 250)));
    await snapshot(tester, 'prescription-review');
    await tester.tap(find.byKey(const Key('ocr-preview-image')));
    await tester.pumpAndSettle();
    await snapshot(tester, 'prescription-photo-dialog');
    await tester.tapAt(const Offset(5, 80));
    await tester.pumpAndSettle();

    await tester.pumpWidget(app(PrescriptionAnalysisPreviewUI(
      medicationScheduleList: schedules,
      previewImagePath: '$root/work/full-audit-20261010/test-prescription.png',
      userSetting: const UserSetting(), onBackRequested: noop, onAnalysisRequested: noop,
      onMedicationScheduleChanged: (_, _) {}, onMedicationScheduleAdded: (_) {},
      isMedicationLookupReview: true, verifiedScheduleIndexes: const {1},
      matchReviews: {0: MedicationMatchReview([MedicationDetail(
        itemName: schedules.first.medicationName, manufacturer: '예시 제조사',
        efficacy: '', usageMethod: '', warning: '')])},
      onCandidateConfirmed: (_, _) {}, onVerifiedOnlyContinueRequested: noop,
    )));
    await tester.ensureVisible(find.byKey(const Key('medication-candidates-0')));
    await snapshot(tester, 'prescription-candidate-action');
    await tester.tap(find.byKey(const Key('medication-candidates-0')));
    await snapshot(tester, 'prescription-candidate-dialog');
    await tester.tap(find.byKey(const Key('medication-candidate-0')));
    await snapshot(tester, 'prescription-candidate-selected');
    await tester.tap(find.text('취소'));
    await tester.pumpWidget(app(PrescriptionAnalysisPreviewUI(
      medicationScheduleList: schedules,
      previewImagePath: '$root/work/full-audit-20261010/test-prescription.png',
      userSetting: const UserSetting(), onBackRequested: noop, onAnalysisRequested: noop,
      onMedicationScheduleChanged: (_, _) {}, onMedicationScheduleAdded: (_) {},
      isMedicationLookupReview: true, verifiedScheduleIndexes: const {0, 1},
      onVerifiedOnlyContinueRequested: noop,
    )));
    await snapshot(tester, 'prescription-confirmed');

    for (final source in MedicationResultSource.values) {
    final resultSchedules = source == MedicationResultSource.prescription ? schedules : [
      MedicationSchedule(medicationName: source == MedicationResultSource.pillPhoto ? '첫 번째 알약' : '예시 복용약',
        prescriptionDate: DateTime(2026, 11, 16), dosage: '1정', intakeTime: '1회',
        medicationTime: 1, scheduleSlotKeys: ['morning']),
    ];
    await tester.pumpWidget(app(CheckResultUI(
      source: source,
      analyzedMedicationList: [for (final s in resultSchedules) AnalyzedMedication(
        schedule: s, detail: const MedicationDetail(itemName: '', efficacy: '', usageMethod: '', warning: ''),
      )],
      prescriptionChangeRadar: source == MedicationResultSource.prescription ? PrescriptionChangeRadar(
        hasPreviousPrescription: true, comparisonStatus: PrescriptionComparisonStatus.comparable,
        previousPrescriptionDate: DateTime(2026, 11, 9), currentPrescriptionDate: DateTime(2026, 11, 16),
        summary: const PrescriptionChangeSummary(scheduleChangedCount: 1, addedCount: 1),
        changes: const [PrescriptionMedicationChange(type: PrescriptionChangeType.scheduleChanged,
          itemName: '소론도정(프레드니솔론)', changedFields: ['total_days'],
          previous: PrescriptionScheduleSnapshot(totalDays: '3일'), current: PrescriptionScheduleSnapshot(totalDays: '7일')),
          PrescriptionMedicationChange(type: PrescriptionChangeType.added, itemName: '타이레놀정500밀리그램(아세트아미노펜)')],
      ) : null,
      userSetting: const UserSetting(), statusMessageProvider: () => '저장 완료',
      savingMedicationIndex: null, completedMedicationSaveIndexes: const {}, isAllMedicationSaving: false,
      onCloseRequested: noop, onTodayScheduleRequested: noop, onSavedMedicationRequested: noop, onHomeRequested: noop,
      onAllMedicationSaveRequested: () async => true, onMedicationSaveRequested: (_, _) async => true,
    )));
    await snapshot(tester, '${source.name}-result');
    if (source == MedicationResultSource.prescription) {
      await tester.tap(find.byKey(const Key('result-medication-toggle-0')));
      await snapshot(tester, 'prescription-result-expanded');
      await tester.tap(find.byKey(const Key('result-medication-toggle-0')));
      await tester.tap(find.byKey(const Key('prescription-radar-toggle')));
      await snapshot(tester, 'prescription-radar');
      await tester.tap(find.byKey(const Key('prescription-radar-toggle')));
    }
    await tester.tap(find.text('전체 저장하기'));
    await tester.pumpAndSettle();
    await snapshot(tester, '${source.name}-save-complete');
    await tester.tap(find.text('홈으로 돌아가기'));
    await tester.pumpAndSettle();
    }

    await tester.pumpWidget(app(PrescriptionAnalysisFailureUI(
      message: '응답이 지연되고 있습니다. 잠시 후 다시 시도해주세요.',
      userSetting: const UserSetting(), failureStep: AnalysisProgressStep.prescriptionRecognition,
      onCameraRetryRequested: noop, onGalleryRetryRequested: noop, onHomeRequested: noop,
    )));
    await snapshot(tester, 'analysis-failure');
  });
}
