import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/authentication_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';

class _SessionControl extends ChangeNotifier implements AuthenticationControl {
  bool retryable = true;
  int calls = 0;
  @override
  bool get shouldAutoRetryBackendSession => retryable;
  @override
  bool get canRetryBackendSession => retryable;
  @override
  bool get isBusy => false;
  @override
  bool get isInitializing => false;
  @override
  Future<void> retryBackendSession() async {
    calls++;
    if (calls == 3) retryable = false;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (const {
      #configurationFailed, #initializationFailed, #emailVerificationRequired,
      #phoneAuthenticationEnabled, #smsCodeRequired,
    }.contains(invocation.memberName)) {
      return false;
    }
    return null;
  }
}

void main() {
  testWidgets('auth screen recovers with backoff without a retry-button tap', (tester) async {
    final control = _SessionControl();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: AuthenticationUI(control: control)));
    await tester.pump();
    expect(control.calls, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(control.calls, 2);
    await tester.pump(const Duration(seconds: 15));
    expect(control.calls, 3);
    await tester.pump(const Duration(minutes: 3));
    expect(control.calls, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    control.dispose();
  });

  testWidgets('background and disposed auth screens stop retrying', (tester) async {
    final control = _SessionControl();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: AuthenticationUI(control: control)));
    await tester.pump();
    expect(control.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 3));
    expect(control.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(control.calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 3));
    expect(control.calls, 2);
    control.dispose();
  });
}
