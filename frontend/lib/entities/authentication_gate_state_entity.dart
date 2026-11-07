import 'package:flutter/foundation.dart';

// 파일명: authentication_gate_state_entity.dart
// 역할: 인증 화면과 인증 처리기가 공유하는 최소 상태 계약을 정의한다.

// 클래스명: AuthenticationGateState
// 역할: 인증 화면 분기에 필요한 최소 상태와 변경 구독 계약이다.
// 주요 책임: 구현체의 초기화·로그인 상태를 화면에 노출한다.
// 속성: isInitializing/isAuthenticated (bool): 초기화 진행과 인증 여부; Listenable: 상태 변경 구독.
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
