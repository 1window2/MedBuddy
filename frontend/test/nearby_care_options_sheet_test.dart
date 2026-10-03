// 병원·약국 선택창의 분기, 취소와 작은 화면의 글씨 확대를 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/nearby_care_options_sheet.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

void main() {
  for (final english in [false, true]) {
    for (final destination in NearbyCareDestination.values) {
      testWidgets('selects ${destination.name}, english=$english', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        NearbyCareDestination? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    selected = await showNearbyCareOptions(
                      context: context,
                      userSetting: UserSetting(
                        language: english ? 'en' : 'ko',
                        fontSize: 20,
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(
          find.text(english ? 'Nearby hospitals' : '근처 병원'),
          findsOneWidget,
        );
        expect(
          find.text(english ? 'Nearby pharmacies' : '근처 약국'),
          findsOneWidget,
        );
        expect(
          find.text(
            english
                ? 'Find hospitals by specialty and check consultation hours.'
                : '진료과별로 주변 병원을 찾고 진료시간을 확인합니다.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            english
                ? 'Find nearby pharmacies and check opening hours.'
                : '주변 약국의 위치와 영업시간을 확인합니다.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byKey(ValueKey('nearby-care-${destination.name}')),
        );
        await tester.pumpAndSettle();
        expect(selected, destination);
      });
    }
  }

  // 바깥 영역을 눌러 닫으면 어느 검색 화면으로도 이동하지 않는다.
  testWidgets('dismiss returns no destination', (tester) async {
    NearbyCareDestination? selected;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showNearbyCareOptions(
                  context: context,
                  userSetting: const UserSetting(),
                );
                completed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(selected, isNull);
  });
}
