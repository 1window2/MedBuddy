// 파일명: medication_schedule_header_test.dart
// 역할: 일정 제목·달력 버튼 정렬과 큰 글씨·좁은 화면에서의 동작을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/widgets/medication_schedule_header.dart';

// 함수이름: main
// 함수역할:
// - 일정 제목·달력 버튼 정렬과 큰 글씨·좁은 화면에서의 동작을 검증한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 공통 설정과 개별 회귀 사례를 등록한다.
void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final english in [false, true]) {
        // 함수이름: testWidgets callback
        // 함수역할:
        // - 폭 320·390과 글씨 배율 1·2에서 한영 제목과 달력 버튼의 세로 중심이 맞고 버튼 동작 및 기본 한글 높이 제한을 지키는지 검증한다.
        // 매개변수:
        // - tester(WidgetTester): 화면과 테스트 시계를 제어하는 도구.
        // 반환값:
        // - Future<void>: 비동기 검증 완료; 기대값과 다르면 테스트가 실패한다.
        testWidgets('schedule title and calendar align $width $scale $english', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final title = english
              ? "Today's Medication Schedule"
              : '오늘의 복약 일정';
          var opened = false;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Column(
                    children: [
                      MedicationScheduleHeader(
                        title: title,
                        actionKey: const Key('history'),
                        actionTooltip: 'History',
                        onAction: () => opened = true,
                        progressLabel: english ? 'Progress' : '복용 진행률',
                        completedCount: 0,
                        totalCount: 5,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          expect(
            tester.getCenter(find.text(title)).dy,
            closeTo(tester.getCenter(find.byKey(const Key('history'))).dy, .1),
          );
          if (!english && scale == 1) {
            expect(
              tester.getSize(find.byType(MedicationScheduleHeader)).height,
              lessThanOrEqualTo(144),
            );
          }
          await tester.tap(find.byKey(const Key('history')));
          expect(opened, isTrue);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
