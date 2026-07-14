import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

void main() {
  testWidgets('corrected medication rows fit the preview at large text size',
      (tester) async {
    await _setViewport(tester, const Size(376, 856));

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: _correctedSchedules(),
          recognitionNotice: '5 medication names were checked.',
          userSetting: const UserSetting(fontSize: 20),
          onBackRequested: () {},
          onAnalysisRequested: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.textContaining('+1'), findsOneWidget);
  });

  testWidgets('preview card remains scrollable on a compact viewport',
      (tester) async {
    await _setViewport(tester, const Size(320, 640));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          );
        },
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: _correctedSchedules(),
          recognitionNotice: '5 medication names were checked.',
          userSetting: const UserSetting(fontSize: 20),
          onBackRequested: () {},
          onAnalysisRequested: () {},
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
