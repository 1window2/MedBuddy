import 'package:flutter/foundation.dart';

// 파일명: authentication_gate_state_entity.dart
// 역할: 인증 화면과 인증 처리기가 공유하는 최소 상태 계약을 정의한다.

// 클래스명: AuthenticationGateState
// 역할: 인증 화면이 관찰할 초기화·로그인 상태만 노출한다.
abstract interface class AuthenticationGateState implements Listenable {
  bool get isInitializing;

  bool get isAuthenticated;
}
