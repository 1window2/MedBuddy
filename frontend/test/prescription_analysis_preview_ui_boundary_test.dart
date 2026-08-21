import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/recognized_text_region_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

void main() {
  testWidgets('OCR 영역을 표시하고 확대 화면에서 개인정보 처리를 안내한다', (tester) async {
    await _setViewport(tester, const Size(376, 856));
    var analysisRequested = false;
    final tempDirectory = Directory.systemTemp.createTempSync(
      'medbuddy-ocr-preview-test-',
    );
    final imageFile = File('${tempDirectory.path}/prescription.png');
    addTearDown(() {
      imageCache.evict(FileImage(imageFile));
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });
    imageFile.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4'
        'nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: const [
            MedicationSchedule(medicationName: '테스트정'),
          ],
          recognizedTextRegions: const [
            RecognizedTextRegion(
              category: 'medication_row',
              text: '테스트정 1정 1일 2회',
              box2d: [100, 80, 260, 920],
            ),
            RecognizedTextRegion(
              category: 'sensitive_info',
              text: '',
              box2d: [20, 40, 80, 400],
            ),
            RecognizedTextRegion(
              category: 'recognized_text',
              text: '일반 복약 안내 문구',
              box2d: [300, 80, 360, 920],
            ),
          ],
          previewImagePath: imageFile.path,
          userSetting: const UserSetting(),
          onBackRequested: () {},
          onAnalysisRequested: () => analysisRequested = true,
          onMedicationScheduleChanged: (_, _) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('ocr-region-0')), findsOneWidget);
    expect(find.byKey(const Key('ocr-sensitive-region-1')), findsOneWidget);
    expect(find.byKey(const Key('ocr-region-2')), findsNothing);
    expect(find.textContaining('개인정보 마스킹 영역'), findsOneWidget);
    expect(find.textContaining('인식 문구:'), findsNothing);
    expect(find.textContaining('서버 DB에는 저장하지 않습니다'), findsNothing);
    expect(find.byKey(const Key('ocr-image-canvas')), findsOneWidget);
    expect(
      find.byKey(const Key('prescription-analyze-button')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('ocr-preview-image')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('ocr-expanded-image-viewer')), findsOneWidget);
    expect(
      find.byKey(const Key('ocr-expanded-sensitive-region-1')),
      findsOneWidget,
    );
    expect(find.text('인식 영역 상세보기'), findsOneWidget);
    expect(find.textContaining('원본 이미지는 이 기기에만 남습니다'), findsOneWidget);
    final interactiveViewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('ocr-expanded-image-viewer')),
    );
    expect(interactiveViewer.maxScale, 5);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('ocr-expanded-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('ocr-expanded-image-viewer')), findsNothing);

    await tester.tap(find.byKey(const Key('prescription-analyze-button')));
    expect(analysisRequested, isTrue);
  });

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

    await tester.ensureVisible(find.byKey(const Key('ocr-edit-0')));
    await tester.pumpAndSettle();
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
    await tester.enterText(
      find.byKey(const Key('ocr-edit-prescription-date')),
      '2026-08-01',
    );
    for (final slotKey in const ['lunch', 'evening', 'bedtime']) {
      final slot = find.byKey(Key('ocr-edit-slot-$slotKey'));
      await tester.ensureVisible(slot);
      await tester.pumpAndSettle();
      await tester.tap(slot);
    }
    final saveButton = find.byKey(const Key('ocr-edit-save'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(updatedIndex, 0);
    expect(updatedSchedule?.medicationName, '애니코프캡슐');
    expect(updatedSchedule?.dosage, '0.5정');
    expect(updatedSchedule?.intakeTime, '1일 2회');
    expect(updatedSchedule?.medicationTime, 5);
    expect(updatedSchedule?.prescriptionDate, DateTime(2026, 8, 1));
    expect(updatedSchedule?.scheduleSlotKeys, ['morning', 'bedtime']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OCR 수정 입력의 길이와 총 투약일 숫자를 제한한다', (tester) async {
    await _setViewport(tester, const Size(320, 560));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: const [
            MedicationSchedule(
              medicationName: '테스트정',
              dosage: '1정',
              intakeTime: '1일 3회',
              medicationTime: 3,
            ),
          ],
          userSetting: const UserSetting(),
          onBackRequested: () {},
          onAnalysisRequested: () {},
          onMedicationScheduleChanged: (_, _) {},
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('ocr-edit-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ocr-edit-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ocr-edit-dosage')),
      List.filled(50, '가').join(),
    );
    await tester.enterText(
      find.byKey(const Key('ocr-edit-frequency')),
      List.filled(50, '나').join(),
    );
    await tester.enterText(find.byKey(const Key('ocr-edit-days')), '12일345');
    await tester.pump();

    final dosageField = tester.widget<TextFormField>(
      find.byKey(const Key('ocr-edit-dosage')),
    );
    final frequencyField = tester.widget<TextFormField>(
      find.byKey(const Key('ocr-edit-frequency')),
    );
    final daysField = tester.widget<TextFormField>(
      find.byKey(const Key('ocr-edit-days')),
    );
    expect(dosageField.controller?.text.length, 40);
    expect(frequencyField.controller?.text.length, 40);
    expect(daysField.controller?.text, '1234');
    expect(tester.takeException(), isNull);
  });

  testWidgets('직접 입력한 조제일자도 달력과 같은 허용 범위를 검증한다', (tester) async {
    await _setViewport(tester, const Size(376, 856));
    MedicationSchedule? updatedSchedule;

    await tester.pumpWidget(
      MaterialApp(
        home: PrescriptionAnalysisPreviewUI(
          medicationScheduleList: const [
            MedicationSchedule(
              medicationName: '테스트정',
              dosage: '1정',
              intakeTime: '1일 1회',
              medicationTime: 3,
            ),
          ],
          userSetting: const UserSetting(),
          onBackRequested: () {},
          onAnalysisRequested: () {},
          onMedicationScheduleChanged: (_, schedule) {
            updatedSchedule = schedule;
          },
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('ocr-edit-0')));
    await tester.tap(find.byKey(const Key('ocr-edit-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ocr-edit-prescription-date')),
      '1999-12-31',
    );
    final saveButton = find.byKey(const Key('ocr-edit-save'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(updatedSchedule, isNull);
    expect(find.text('2000-01-01부터 오늘 기준 1년 이내 날짜를 입력해주세요.'), findsOneWidget);
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
