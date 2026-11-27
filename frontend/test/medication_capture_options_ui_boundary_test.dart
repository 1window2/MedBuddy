// 파일명: medication_capture_options_ui_boundary_test.dart
// 역할: 약 등록 화면의 작업 전달, 사진 출처 시트의 이전 단계 복귀와 큰 글씨 접근성을 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/medication_capture_options_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 함수이름: main
// 함수역할: 공통 약 등록 화면의 탐색·취소 테스트를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  for (final language in ['ko', 'en']) {
    for (final includePhotoDose in [true, false]) {
      // 함수이름: 등록 작업 선택과 단계 뒤로가기
      // 함수역할:
      // - 좁은 화면·큰 글씨·두 언어에서 사진 출처 시트를 시스템 뒤로가기로 닫으면 작업 없이 등록 화면으로 돌아오고,
      //   낱알약 식별은 촬영 방식 시트 없이 바로 pills 작업을, 직접 등록은 manual 작업을 전달하며 등록 화면을 유지하는지 확인한다.
      // - 사진으로 복용 기록은 includePhotoDose가 true일 때만 보이고 photoDose 작업을 전달한다.
      // 매개변수:
      // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
      // 반환값:
      // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
      testWidgets('약 등록 작업 선택 $language photoDose=$includePhotoDose', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final selected = <MedicationCaptureTask>[];
        var sourceRequests = 0;
        final english = language == 'en';
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    await showMedicationCaptureTaskOptions(
                      context: context,
                      userSetting: UserSetting(
                        language: language,
                        fontSize: 20,
                      ),
                      includePhotoDose: includePhotoDose,
                      onTaskSelected: (_, task) async => selected.add(task),
                      onSourceSelected: (_, _) async => sourceRequests++,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final page = find.byKey(const Key('medication-registration-page'));
        expect(page, findsOneWidget);
        expect(
          find.byKey(const ValueKey('registrationPhotoDoseTile')),
          includePhotoDose ? findsOneWidget : findsNothing,
        );

        // 시스템 뒤로 가기는 사진 출처 시트만 닫고 작업 없이 등록 화면으로 돌아간다.
        final prescription = find.byKey(
          const ValueKey('registrationPrescriptionTile'),
        );
        await _tapTop(tester, prescription);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('photoSourceCamera')), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('photoSourceCamera')), findsNothing);
        expect(page, findsOneWidget);
        expect(find.text(english ? 'Add manually' : '직접 등록'), findsOneWidget);
        expect(selected, isEmpty);
        expect(sourceRequests, 0);

        // 낱알약 식별은 촬영 방식 시트 없이 바로 작업을 전달한다.
        final pill = find.text(english ? 'Identify a loose pill' : '낱알약 식별');
        await _tapTop(tester, pill);
        await tester.pumpAndSettle();
        expect(selected, [MedicationCaptureTask.pills]);
        expect(find.byType(BottomSheet), findsNothing);

        final manual = find.text(english ? 'Add manually' : '직접 등록');
        await _tapTop(tester, manual);
        await tester.pumpAndSettle();
        expect(selected, [
          MedicationCaptureTask.pills,
          MedicationCaptureTask.manual,
        ]);

        if (includePhotoDose) {
          final photoDose = find.byKey(
            const ValueKey('registrationPhotoDoseTile'),
          );
          await _tapTop(tester, photoDose);
          await tester.pumpAndSettle();
          expect(selected.last, MedicationCaptureTask.photoDose);
        }
        // 등록 화면은 시작한 작업이 끝나 돌아올 수 있도록 남는다.
        expect(page, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

// 함수이름: _tapTop
// 함수역할: 대상을 화면에 보이게 한 뒤 위쪽 가장자리 근처를 누른다. 테스트 글꼴의 영어 2배 글씨에서는
//   타일이 화면보다 길어져 가운데가 화면 밖에 놓이기 때문이다.
// 매개변수: tester (WidgetTester): 테스트 도구; finder (Finder): 누를 대상.
// 반환값: 누르기와 화면 갱신이 끝나면 완료.
Future<void> _tapTop(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tapAt(tester.getTopLeft(finder) + const Offset(12, 12));
}
