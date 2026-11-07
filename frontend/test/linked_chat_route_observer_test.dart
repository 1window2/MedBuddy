// File Name: linked_chat_route_observer_test.dart
// Role: Verifies chat route tracking across overlays, removals, and returns to an existing conversation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/linked_chat_ui_boundary.dart';

// Function Name: main
// Description:
// - Register a navigator-backed check of chat-route tracking across overlays, replacement, pop, and explicit removal.
// Parameters:
// - None.
// Returns:
// - void; no return value.
void main() {
  // Function Name: 열린 채팅 경로만 추적하고 닫거나 제거하면 지운다
  // Description:
  // - Track a chat beneath an unrelated overlay, retain it when only the overlay is popped, and clear or replace tracked links when their routes leave the navigator.
  // Parameters:
  // - tester (WidgetTester): drives the screen and inspects state, gestures, and rendering.
  // Returns:
  // - Future<void>; completes after the asynchronous assertions.
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
    // Function Name: chat
    // Description:
    // - Create an empty route with the canonical chat name so observer behavior can be tested without rendering chat content.
    // Parameters:
    // - linkId (int): link encoded into the route name.
    // Returns:
    // - Route<void>; a MaterialPageRoute associated with that chat.
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

    // Popping only an overlay, as notification routing does, keeps the chat tracked.
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
