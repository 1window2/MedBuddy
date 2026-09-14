// 파일명: authentication_session_recovery_test.dart
// 역할: 세션 자동 복구와 정상 생명주기 전환에 따른 재시도 중단을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/authentication_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/authentication_control.dart';

// Class Name: _SessionControl
// Role: Emulate a session that recovers on its third retry without network calls.
// Attributes: retryable tracks recovery state; calls counts retry requests.
class _SessionControl extends ChangeNotifier implements AuthenticationControl {
  bool retryable = true;
  int calls = 0;
  // Function Name: shouldAutoRetryBackendSession
  // Description: Expose retry eligibility. Parameters: none. Returns: recovery state.
  @override
  bool get shouldAutoRetryBackendSession => retryable;
  // Function Name: canRetryBackendSession
  // Description: Expose manual retry eligibility. Parameters: none. Returns: recovery state.
  @override
  bool get canRetryBackendSession => retryable;
  // Function Name: isBusy
  // Description: Keep the fake idle. Parameters: none. Returns: false.
  @override
  bool get isBusy => false;
  // Function Name: isInitializing
  // Description: Skip initialization in this fake. Parameters: none. Returns: false.
  @override
  bool get isInitializing => false;
  // Function Name: retryBackendSession
  // Description: Count retries and notify recovery on attempt three.
  // Parameters: none. Returns: completion after listeners are notified.
  @override
  Future<void> retryBackendSession() async {
    calls++;
    if (calls == 3) {
      retryable = false;
    }
    notifyListeners();
  }

  // Function Name: noSuchMethod
  // Description: Supply unused authentication state for the screen fixture.
  // Parameters: invocation identifies the member. Returns: false flags or null.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (const {
      #configurationFailed,
      #initializationFailed,
      #emailVerificationRequired,
      #phoneAuthenticationEnabled,
      #smsCodeRequired,
    }.contains(invocation.memberName)) {
      return false;
    }
    return null;
  }
}

// 함수이름: main
// 함수역할: 세션 복구 회귀 테스트를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  // Function Name: automatic recovery test
  // Description: Verify retry backoff and termination after successful recovery.
  // Parameters: tester controls the widget and clock. Returns: completed assertions.
  testWidgets('auth screen recovers with backoff without a retry-button tap', (
    tester,
  ) async {
    final control = _SessionControl();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(home: AuthenticationUI(control: control)),
    );
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

  // 함수이름: 백그라운드·화면 종료 재시도 테스트
  // 함수역할: 정상 상태 전환을 거쳐 재시도가 멈추고 복귀 시 재개되는지 검증한다.
  // 매개변수: tester: 화면·시간 제어기. 반환값: 비동기 검증 완료.
  testWidgets('background and disposed auth screens stop retrying', (
    tester,
  ) async {
    final control = _SessionControl();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(home: AuthenticationUI(control: control)),
    );
    await tester.pump();
    expect(control.calls, 1);
    // Flutter 생명주기의 중간 상태를 생략하지 않고 백그라운드 이동을 재현한다.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 3));
    expect(control.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(control.calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 3));
    expect(control.calls, 2);
    control.dispose();
  });
}
