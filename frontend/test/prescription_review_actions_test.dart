// 파일명: prescription_review_actions_test.dart
// 역할: 긴 처방전에서도 하단의 재조회·부분 진행 동작에 바로 접근할 수 있는지 검증한다.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

// 함수이름: main
// 함수역할:
// - 한영·큰 글씨 화면에서 긴 검토 목록과 고정 하단 동작의 접근성을 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례와 준비·정리 훅은 테스트 프레임워크에서 실행한다.
void main() {
  // 함수이름: setUpAll callback
  // 함수역할:
  // - MEDBUDDY_TEST_FONT가 주어지면 한영 테스트 글꼴과 MaterialIcons를 로드하여 선택적 기준 이미지 비교의 글꼴 차이를 줄인다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
  for (final english in [false, true]) {
    for (final large in [false, true]) {
      // 함수이름: testWidgets callback
      // 함수역할:
      // - 12개 약 검토에서도 재조회·부분 진행 버튼이 스크롤 없이 보이고 한 약 검증 뒤에만 진행을 허용하며 취소는 유지, 확인은 한 번만 진행하는지 검증한다.
      // 매개변수:
      // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
      // 반환값:
      // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
      testWidgets('하단 두 버튼은 스크롤 없이 보인다 en=$english large=$large', (
        tester,
      ) async {
        tester.view.physicalSize = Size(large ? 320 : 390, large ? 640 : 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var verified = <int>{};
        var continued = 0;
        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: MedBuddyTheme.light().copyWith(
              textTheme: MedBuddyTheme.light().textTheme.apply(
                fontFamily: Platform.environment['MEDBUDDY_TEST_FONT'] == null
                    ? null
                    : 'Noto Sans KR',
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
              child: child!,
            ),
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return PrescriptionAnalysisPreviewUI(
                  medicationScheduleList: List.generate(
                    12,
                    (index) => MedicationSchedule(
                      medicationName: '시험약 ${index + 1}',
                      dosage: '1정',
                    ),
                  ),
                  userSetting: UserSetting(language: english ? 'en' : 'ko'),
                  isMedicationLookupReview: true,
                  verifiedScheduleIndexes: verified,
                  lookupStatuses: const {1: MedicationLookupStatus.failed},
                  onBackRequested: () {},
                  onAnalysisRequested: () {},
                  onMedicationScheduleChanged: (_, _) {},
                  onVerifiedOnlyContinueRequested: () => continued++,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final retry = find.byKey(const Key('prescription-analyze-button'));
        final next = find.byKey(
          const Key('continue-with-verified-medications'),
        );
        expect(retry.hitTestable(), findsOneWidget);
        expect(next.hitTestable(), findsOneWidget);
        expect(tester.widget<FilledButton>(next).onPressed, isNull);
        expect(
          tester.getRect(retry).right,
          lessThan(tester.getRect(next).left),
        );
        expect(
          tester.getRect(retry).top,
          closeTo(tester.getRect(next).top, .1),
        );
        expect(tester.getRect(retry).height, tester.getRect(next).height);
        expect(find.textContaining('공공데이터 약품 정보 서비스'), findsNothing);
        rebuild(() => verified = {0});
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
        if (Platform.environment['MEDBUDDY_CAPTURE_PREVIEWS'] == 'true') {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../.dart_tool/result_previews/review-actions-${english ? 'en' : 'ko'}-${large ? 'large' : 'normal'}.png',
            ),
          );
        }
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(continued, 0);
        await tester.tap(
          find.byKey(const Key('cancel-verified-only-continue')),
        );
        await tester.pumpAndSettle();
        expect(continued, 0);
        await tester.tap(next);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('confirm-verified-only-continue')),
        );
        await tester.pumpAndSettle();
        expect(continued, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
