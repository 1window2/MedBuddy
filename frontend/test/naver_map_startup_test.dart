// 파일명: naver_map_startup_test.dart
// 역할: 네이버 지도 SDK 초기화가 앱 시작과 지도 화면 사이에서 한 번만 실행되고, 실패하면 다음 지도 화면에서 다시 시도되는지 검증한다.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/naver_map_config.dart';

// 함수이름: main
// 함수역할:
// - 지도 SDK 초기화 공유·미설정 빌드·실패 후 재시도 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 동시에 들어온 요청은 같은 초기화를 기다리고 SDK는 한 번만 초기화된다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('동시에 요청해도 SDK는 한 번만 초기화된다', () async {
    var calls = 0;
    final gate = Completer<void>();
    final startup = NaverMapStartup(
      configured: true,
      initialize: () {
        calls += 1;
        return gate.future;
      },
    );

    final first = startup.ensureInitialized();
    final second = startup.ensureInitialized();
    expect(startup.isReady, isFalse);
    gate.complete();

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(await startup.ensureInitialized(), isTrue);
    expect(startup.isReady, isTrue);
    expect(calls, 1);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 지도 설정이 없는 빌드는 네이티브 지도 라이브러리를 불러오지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('지도 설정이 없는 빌드는 SDK를 초기화하지 않는다', () async {
    var calls = 0;
    final startup = NaverMapStartup(
      configured: false,
      initialize: () async => calls += 1,
    );

    expect(await startup.ensureInitialized(), isFalse);
    expect(calls, 0);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 실패한 초기화는 보고되고 다음 요청에서 다시 시도된다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('실패한 초기화는 보고되고 다음 요청에서 다시 시도된다', () async {
    final reported = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousOnError);
    var calls = 0;
    final startup = NaverMapStartup(
      configured: true,
      initialize: () async {
        calls += 1;
        if (calls == 1) {
          throw StateError('channel unavailable');
        }
      },
    );

    expect(await startup.ensureInitialized(), isFalse);
    expect(startup.isReady, isFalse);
    expect(reported.single.library, 'MedBuddy Naver Map');
    expect(await startup.ensureInitialized(), isTrue);
    expect(calls, 2);
  });
}
