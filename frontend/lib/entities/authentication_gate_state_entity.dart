import 'package:flutter/foundation.dart';

// 파일명: authentication_gate_state_entity.dart
// 역할: 인증 화면과 인증 처리기가 공유하는 최소 상태 계약을 정의한다.

// 클래스명: AuthenticationGateState
// 역할: 인증 화면이 구독할 초기화·로그인 상태의 최소 계약이다.
// 주요 책임:
// - 구체 인증 서비스에 의존하지 않고 Listenable 상태 변경으로 인증 게이트를 갱신하게 한다.
abstract interface class AuthenticationGateState implements Listenable {
  // 함수이름: isInitializing
  // 함수역할: 인증 초기화가 진행 중인지 제공해 로딩 화면과 로그인 화면을 구분하게 한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 인증 초기화가 진행 중인지 제공해 로딩 화면과 로그인 화면을 구분하게 한다.
  bool get isInitializing;

  // 함수이름: isAuthenticated
  // 함수역할: 앱 본 화면에 접근할 인증 세션이 있는지 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - bool: 앱 본 화면에 접근할 인증 세션이 있는지 제공한다.
  bool get isAuthenticated;
}
