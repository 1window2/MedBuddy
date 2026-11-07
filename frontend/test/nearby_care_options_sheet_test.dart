// 파일명: nearby_care_options_sheet_test.dart
// 역할: 병원·약국 선택창의 분기, 취소와 작은 화면의 글씨 확대를 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/nearby_care_options_sheet.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 함수이름: main
// 함수역할:
// - 병원·약국 선택창의 분기, 취소와 작은 화면의 글씨 확대를 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 공통 설정과 개별 회귀 사례를 등록한다.
void main() {
  for (final english in [false, true]) {
    for (final destination in NearbyCareDestination.values) {
      // 함수이름: testWidgets callback
      // 함수역할:
      // - 320×640 화면과 글꼴 크기 20에서 한영 병원·약국 설명을 표시하고 누른 항목의 목적지를 정확히 반환하는지 검증한다.
      // 매개변수:
      // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
      // 반환값:
      // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
  // 함수이름: testWidgets callback
  // 함수역할:
  // - 선택창 바깥을 눌러 닫으면 대기 중 호출은 완료되지만 검색 목적지는 null로 반환되는지 검증한다.
  // 매개변수:
  // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
  // 반환값:
  // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
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
