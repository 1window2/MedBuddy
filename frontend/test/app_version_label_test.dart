// 파일명: app_version_label_test.dart
// 역할: 설정 화면의 앱 버전 표시가 누락되지 않는지 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/widgets/app_version_label.dart';

void main() {
  testWidgets('설정 화면에 전달된 앱 버전을 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppVersionLabel(version: '0.1.1')),
      ),
    );

    expect(find.byKey(const ValueKey('appVersionLabel')), findsOneWidget);
    expect(find.text('MedBuddy v0.1.1'), findsOneWidget);
  });
}
