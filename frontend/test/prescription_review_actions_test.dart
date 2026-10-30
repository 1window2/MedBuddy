// 긴 처방전에서도 하단의 재조회·부분 진행 동작에 바로 접근할 수 있는지 검증한다.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';

void main() {
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
