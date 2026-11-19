// 파일명: medication_review_registration_layout_test.dart
// 역할: 사진 기반 약 등록의 전체 검토 페이지와 고정 저장 버튼을 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/medication_schedule_review_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/medication_review_image_gallery.dart';

// 함수이름: main
// 함수역할: 약 등록 검토의 사진·접이식 표·작은 화면·취소 동작을 검증한다.
// 매개변수: 없음. 반환값: 없음; 검증 사례를 등록한다.
void main() {
  // 함수이름: 전체 페이지 검토 테스트
  // 함수역할: 바닥 시트 대신 전체 페이지에서 사진과 같은 형식의 복약 표를 확인한다.
  // 매개변수: tester: 위젯 검사 도구. 반환값: 검증 완료 Future.
  testWidgets('사진 검토는 전체 페이지와 접이식 2열 표를 사용한다', (tester) async {
    await _openReview(tester, size: const Size(412, 915));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(MedicationReviewImageGallery), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
    expect(scaffold.backgroundColor, MedBuddyColors.pageBackground);
    final edit = find.byKey(const Key('schedule-review-edit-0'));
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    final dose = find.byKey(const Key('schedule-review-cell-0-dosage'));
    final duration = find.byKey(const Key('schedule-review-cell-0-duration'));
    expect(tester.getTopLeft(dose).dy, tester.getTopLeft(duration).dy);
    expect(
      tester.getTopLeft(dose).dx,
      lessThan(tester.getTopLeft(duration).dx),
    );
    expect(tester.getSize(dose).width, tester.getSize(duration).width);
    await tester.tap(find.byKey(const Key('schedule-review-toggle-0')));
    await tester.pumpAndSettle();
    expect(dose, findsNothing);
    expect(
      find.byKey(const Key('schedule-review-confirm')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(640, 360)]) {
    // 함수이름: 큰 글씨 검토 테스트
    // 함수역할: 큰 글씨와 가로 화면에서도 사진과 약 목록을 넘기고 저장할 수 있는지 확인한다.
    // 매개변수: tester: 위젯 검사 도구. 반환값: 검증 완료 Future.
    testWidgets('큰 글씨와 $size에서 저장 버튼이 항상 보인다', (tester) async {
      List<MedicationSchedule>? result;
      await _openReview(
        tester,
        size: size,
        scale: 2,
        onReviewed: (value) => result = value,
      );
      await tester.drag(
        find.byKey(const Key('schedule-review-list')),
        const Offset(0, -650),
      );
      await tester.pumpAndSettle();
      final confirm = find.byKey(const Key('schedule-review-confirm'));
      expect(confirm.hitTestable(), findsOneWidget);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(result, hasLength(2));
      expect(result!.first.medicationName, '타이레놀정500밀리그램(아세트아미노펜)');
      expect(result!.last.intakeTime, '격일');
      expect(result!.last.dailyFrequencyCount, 1);
      expect(result!.last.slotKeys, ['morning']);
      expect(tester.takeException(), isNull);
    });
  }
}

// 함수이름: _openReview
// 함수역할: 두 장의 촬영 사진과 서로 다른 복용 주기를 가진 약 두 건을 검토 화면에 제공한다.
// 매개변수: tester: 화면 도구; size/scale: 화면 크기와 글씨 배율; onReviewed: 반환 목록 관찰.
// 반환값: 검토 페이지 진입이 끝난 Future.
Future<void> _openReview(
  WidgetTester tester, {
  required Size size,
  double scale = 1,
  ValueChanged<List<MedicationSchedule>?>? onReviewed,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await showMedicationScheduleReview(
                context: context,
                userSetting: const UserSetting(),
                initialSchedules: [
                  MedicationSchedule(
                    medicationName: '타이레놀정500밀리그램(아세트아미노펜)',
                    prescriptionDate: DateTime(2026, 11, 16),
                    dosage: '1정',
                    intakeTime: '2회',
                    medicationTime: 3,
                    scheduleSlotKeys: const ['morning', 'evening'],
                  ),
                  MedicationSchedule(
                    medicationName: '검토용 두 번째 약',
                    prescriptionDate: DateTime(2026, 11, 16),
                    dosage: '1정',
                    intakeTime: '격일, 1일 1회',
                    medicationTime: 7,
                    scheduleSlotKeys: const ['morning'],
                  ),
                ],
                photos: [
                  MedicationReviewPhoto(
                    title: '첫 번째 촬영 사진',
                    imageBuilder: (context) =>
                        const ColoredBox(color: Colors.blue),
                  ),
                  MedicationReviewPhoto(
                    title: '두 번째 촬영 사진',
                    imageBuilder: (context) =>
                        const ColoredBox(color: Colors.green),
                  ),
                ],
              );
              onReviewed?.call(result);
            },
            child: const Text('검토 열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('검토 열기'));
  await tester.pumpAndSettle();
}
