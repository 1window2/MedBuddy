import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

void main() {
  testWidgets('corrected medication rows fit the preview at large text size', (
    tester,
  ) async {
    await _setViewport(tester, const Size(376, 856));

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: _correctedSchedules(),
          recognitionNotice: '5 medication names were checked.',
          userSetting: const UserSetting(fontSize: 20),
          onBackRequested: () {},
          onAnalysisRequested: () {},
          onMedicationScheduleChanged: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.textContaining('+1'), findsOneWidget);
  });

  testWidgets('preview card remains scrollable on a compact viewport', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 640));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          );
        },
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: _correctedSchedules(),
          recognitionNotice: '5 medication names were checked.',
          userSetting: const UserSetting(fontSize: 20),
          onBackRequested: () {},
          onAnalysisRequested: () {},
          onMedicationScheduleChanged: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('검토 필요 배지와 수정 버튼이 있는 네 행이 넘치지 않는다', (tester) async {
    await _setViewport(tester, const Size(376, 856));

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: List.generate(
            4,
            (index) => MedicationSchedule(
              medicationName: '검토가 필요한 긴 약 이름 ${index + 1}',
              intakeTime: '${index + 1}',
              nameCorrectionSource: 'unverified',
            ),
          ),
          userSetting: const UserSetting(),
          onBackRequested: () {},
          onAnalysisRequested: () {},
          onMedicationScheduleChanged: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('검토 필요'), findsNWidgets(4));
    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('OCR 수정값을 콜백으로 전달한다', (tester) async {
    await _setViewport(tester, const Size(376, 856));
    MedicationSchedule? updatedSchedule;
    var updatedIndex = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: const [
            MedicationSchedule(
              medicationName: '에니코프캡슐',
              dosage: '1정',
              intakeTime: '1일 3회',
              medicationTime: 4,
              nameCorrectionSource: 'unverified',
            ),
          ],
          userSetting: const UserSetting(),
          onBackRequested: () {},
          onAnalysisRequested: () {},
          onMedicationScheduleChanged: (index, schedule) {
            updatedIndex = index;
            updatedSchedule = schedule;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('ocr-edit-0')));
    await tester.pumpAndSettle();
    expect(find.text('OCR 인식 결과 수정'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ocr-edit-name')), '애니코프캡슐');
    await tester.enterText(find.byKey(const Key('ocr-edit-dosage')), '0.5정');
    await tester.enterText(
      find.byKey(const Key('ocr-edit-frequency')),
      '1일 2회',
    );
    await tester.enterText(find.byKey(const Key('ocr-edit-days')), '5');
    await tester.tap(find.byKey(const Key('ocr-edit-save')));
    await tester.pumpAndSettle();

    expect(updatedIndex, 0);
    expect(updatedSchedule?.medicationName, '애니코프캡슐');
    expect(updatedSchedule?.dosage, '0.5정');
    expect(updatedSchedule?.intakeTime, '1일 2회');
    expect(updatedSchedule?.medicationTime, 5);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

List<MedicationSchedule> _correctedSchedules() {
  return List.generate(
    5,
    (index) => MedicationSchedule(
      medicationName: 'Corrected medication name ${index + 1}',
      rawMedicationName: 'OCR medication ${index + 1}',
      nameCorrectionSource: 'local_catalog_prefix',
      intakeTime: '${index.isEven ? 3 : 2}회',
    ),
    growable: false,
  );
}
