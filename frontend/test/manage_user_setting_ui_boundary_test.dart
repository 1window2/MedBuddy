import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manage_user_setting_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 파일명: manage_user_setting_ui_boundary_test.dart
// 역할: 환경설정 저장 중복 방지와 실패 복구 동작을 검증한다.

void main() {
  testWidgets('환경설정 저장 실패 후 버튼을 복구하고 재시도를 허용한다', (tester) async {
    final saveRequest = Completer<void>();
    var requestCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ManageUserSettingUI(
          initialSetting: const UserSetting(),
          onSettingSaveRequested:
              ({
                required fontSizeOption,
                required readingSpeedOption,
                required language,
              }) {
                requestCount += 1;
                return saveRequest.future;
              },
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '저장하기'));
    await tester.pump();
    expect(find.text('저장 중...'), findsOneWidget);
    expect(requestCount, 1);

    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(requestCount, 1);

    saveRequest.completeError(StateError('storage unavailable'));
    await tester.pumpAndSettle();

    expect(find.text('설정을 저장하지 못했습니다.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '저장하기'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '저장하기'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
