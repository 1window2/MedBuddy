// 파일명: linked_chat_route_observer_test.dart
// 역할: 채팅 알림이 이미 열린 대화를 새로 쌓지 않도록 열린 채팅 경로 추적을 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/linked_chat_ui_boundary.dart';

// 함수이름: main
// 함수역할: 채팅 경로의 쌓기·닫기·제거·교체에 따른 추적 결과를 검사한다. 매개변수: 없음. 반환값: 없음.
void main() {
  testWidgets('열린 채팅 경로만 추적하고 닫거나 제거하면 지운다', (tester) async {
    final chatRoutes = LinkedChatRouteObserver();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [chatRoutes],
        home: const SizedBox.shrink(),
      ),
    );
    Route<void> chat(int linkId) => MaterialPageRoute<void>(
      settings: RouteSettings(name: linkedChatRouteName(linkId)),
      builder: (_) => const SizedBox.shrink(),
    );

    navigator.currentState!.push(chat(3));
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
    );
    await tester.pumpAndSettle();
    expect(chatRoutes.isOpen(3), isTrue);
    expect(chatRoutes.isOpen(4), isFalse);

    // 알림 처리처럼 채팅 위의 화면만 닫으면 채팅은 계속 열린 것으로 남는다.
    navigator.currentState!.popUntil(
      (route) => route.settings.name == linkedChatRouteName(3) || route.isFirst,
    );
    await tester.pumpAndSettle();
    expect(chatRoutes.isOpen(3), isTrue);

    navigator.currentState!.pushReplacement(chat(4));
    await tester.pumpAndSettle();
    expect(chatRoutes.isOpen(3), isFalse);
    expect(chatRoutes.isOpen(4), isTrue);

    navigator.currentState!.popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    expect(chatRoutes.isOpen(4), isFalse);

    final removed = chat(5);
    navigator.currentState!.push(removed);
    await tester.pumpAndSettle();
    navigator.currentState!.removeRoute(removed);
    await tester.pumpAndSettle();
    expect(chatRoutes.isOpen(5), isFalse);
  });
}
