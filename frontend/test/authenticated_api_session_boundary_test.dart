// 파일명: authenticated_api_session_boundary_test.dart
// 역할: 지연된 인증 실패가 요청을 시작한 세션 이외의 계정을 만료시키지 않는지 검증한다.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/services/authenticated_api_client.dart';

// 함수이름: main
// 함수역할:
// - 요청 중 세션 변경과 전역 인증 실패 처리기의 계정 격리 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 비동기 검증은 테스트 프레임워크에서 실행한다.
void main() {
  for (final transition in [
    'same',
    'other-account',
    'signed-out',
    'closed',
    'unavailable',
  ]) {
    // 함수이름: 지연된 401 응답의 세션 소유권 테스트
    // 함수역할:
    // - 요청 시작 뒤 계정 교체·로그아웃·클라이언트 종료·토큰 조회 실패를 재현한다.
    // - 401 응답은 그대로 반환하되 동일 세션일 때만 만료 처리기가 한 번 호출되어야 한다.
    // 매개변수:
    // - 없음; transition(String)이 요청과 응답 사이의 상태 전환을 정한다.
    // 반환값:
    // - Future<void>: 응답 상태와 만료 호출 횟수 검증 완료; 불일치하면 실패한다.
    test(
      'a delayed 401 only invalidates its current session: $transition',
      () async {
        String? token = 'account-a-token';
        var unavailable = false;
        var invalidations = 0;
        final started = Completer<void>();
        final response = Completer<http.Response>();
        final client = AuthenticatedApiClient(
          inner: MockClient((request) {
            expect(request.headers['authorization'], 'Bearer account-a-token');
            started.complete();
            return response.future;
          }),
          tokenProvider: () async {
            if (unavailable) throw StateError('token temporarily unavailable');
            return token;
          },
          appCheckRequired: false,
          onUnauthorized: () async {
            invalidations++;
          },
          trustedBaseUri: Uri.parse('https://api.example.test'),
        );
        addTearDown(client.close);
        final pending = client.get(
          Uri.parse('https://api.example.test/schedule'),
        );
        await started.future;
        if (transition == 'other-account') token = 'account-b-token';
        if (transition == 'signed-out') token = null;
        if (transition == 'closed') client.close();
        if (transition == 'unavailable') unavailable = true;
        response.complete(http.Response('{}', 401));

        expect((await pending).statusCode, 401);
        expect(invalidations, transition == 'same' ? 1 : 0);
      },
    );
  }

  // 함수이름: 전역 인증 실패 처리기의 계정 격리 테스트
  // 함수역할:
  // - 요청 처리 중 다른 계정 토큰으로 바뀌면 전역 처리기도 호출하지 않는지 검증한다.
  // - 테스트 종료 시 원래 전역 처리기를 복원하여 다른 사례에 영향을 주지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 401 반환과 만료 호출 없음의 검증 완료.
  test(
    'the global unauthorized handler also ignores another account response',
    () async {
      String? token = 'account-a-token';
      var invalidations = 0;
      final previous = AuthenticatedApiClient.defaultOnUnauthorized;
      AuthenticatedApiClient.defaultOnUnauthorized = () async {
        invalidations++;
      };
      addTearDown(
        () => AuthenticatedApiClient.defaultOnUnauthorized = previous,
      );
      final client = AuthenticatedApiClient(
        inner: MockClient((_) async {
          token = 'account-b-token';
          return http.Response('{}', 401);
        }),
        tokenProvider: () async => token,
        appCheckRequired: false,
        trustedBaseUri: Uri.parse('https://api.example.test'),
      );
      addTearDown(client.close);

      expect(
        (await client.get(Uri.parse('https://api.example.test'))).statusCode,
        401,
      );
      expect(invalidations, 0);
    },
  );
}
