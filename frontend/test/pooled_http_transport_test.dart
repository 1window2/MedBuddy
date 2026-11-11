// 파일명: pooled_http_transport_test.dart
// 역할: 화면별 API 클라이언트가 연결 풀을 함께 쓰면서도 닫힐 때 자기 요청만 중단하는지 검증한다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medbuddy_frontend/services/pooled_http_transport.dart';

// 클래스명: _RecordingTransport
// 역할: 공용 전송 대역으로 받은 요청과 본문을 기록하고 응답을 돌려준다.
// 속성: requests/bodies: 받은 요청과 읽은 본문.
class _RecordingTransport extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final bodies = <String>[];
  bool closed = false;

  // 함수이름: send
  // 함수역할: 요청 본문을 끝까지 읽어 기록하고 200 응답을 돌려준다.
  // 매개변수: request: 전달된 요청.
  // 반환값: 빈 본문의 200 응답.
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(await request.finalize().bytesToString());
    return http.StreamedResponse(const Stream.empty(), 200);
  }

  // 함수이름: close
  // 함수역할: 공용 전송이 닫혔는지 기록한다.
  // 매개변수: 없음. 반환값: 없음.
  @override
  void close() => closed = true;
}

// 함수이름: main
// 함수역할: 공용 연결 풀 전달, 소유자별 중단, 닫힌 뒤 요청 거부 사례를 등록한다.
// 매개변수: 없음.
// 반환값: 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  test('요청은 헤더와 본문을 유지한 채 공용 전송으로 간다', () async {
    final shared = _RecordingTransport();
    final transport = PooledHttpTransport(shared: shared);
    final request = http.Request('POST', Uri.parse('https://api.test/x'))
      ..headers['authorization'] = 'Bearer t'
      ..body = jsonEncode({'a': 1});

    final response = await transport.send(request);

    expect(response.statusCode, 200);
    final sent = shared.requests.single;
    expect(sent.method, 'POST');
    expect(sent.url, Uri.parse('https://api.test/x'));
    expect(sent.headers['authorization'], 'Bearer t');
    expect(shared.bodies.single, '{"a":1}');
    expect(sent, isA<http.Abortable>());
  });

  // 함수이름: 멀티파트 요청 전달 테스트
  // 함수역할: 알약 사진 업로드처럼 멀티파트 요청을 보내도 경계가 든 Content-Type과 파일 부분이 그대로 가는지 검증한다.
  // 매개변수: 없음. 반환값: Future<void>; 불일치 시 테스트 실패.
  test('멀티파트 요청은 경계가 든 Content-Type과 파일 부분을 유지한다', () async {
    final shared = _RecordingTransport();
    final transport = PooledHttpTransport(shared: shared);
    final request =
        http.MultipartRequest('POST', Uri.parse('https://api.test/pill'))
          ..files.add(
            http.MultipartFile.fromBytes(
              'front',
              utf8.encode('jpeg'),
              filename: 'pill-front.jpg',
            ),
          );

    await transport.send(request);

    final contentType = shared.requests.single.headers['content-type'] ?? '';
    expect(contentType, startsWith('multipart/form-data; boundary='));
    final boundary = contentType.split('boundary=').last;
    expect(shared.bodies.single, contains('--$boundary'));
    expect(
      shared.bodies.single,
      contains('name="front"; filename="pill-front.jpg"'),
    );
  });

  test('닫으면 자기 요청만 중단하고 공용 전송은 열어 둔다', () async {
    final shared = _RecordingTransport();
    final first = PooledHttpTransport(shared: shared);
    final second = PooledHttpTransport(shared: shared);
    await first.get(Uri.parse('https://api.test/a'));
    await second.get(Uri.parse('https://api.test/b'));
    var firstAborted = false;
    var secondAborted = false;
    unawaited(
      (shared.requests[0] as http.Abortable).abortTrigger!.then(
        (_) => firstAborted = true,
      ),
    );
    unawaited(
      (shared.requests[1] as http.Abortable).abortTrigger!.then(
        (_) => secondAborted = true,
      ),
    );

    first.close();
    await Future<void>.delayed(Duration.zero);

    expect(firstAborted, isTrue);
    expect(secondAborted, isFalse);
    expect(shared.closed, isFalse);
    await expectLater(
      first.get(Uri.parse('https://api.test/c')),
      throwsA(isA<http.RequestAbortedException>()),
    );
    expect(shared.requests, hasLength(2));
  });

  test('호출자의 중단 신호도 그대로 전달한다', () async {
    final shared = _RecordingTransport();
    final transport = PooledHttpTransport(shared: shared);
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      Uri.parse('https://api.test/a'),
      abortTrigger: abort.future,
    );
    await transport.send(request);
    var aborted = false;
    unawaited(
      (shared.requests.single as http.Abortable).abortTrigger!.then(
        (_) => aborted = true,
      ),
    );

    abort.complete();
    await Future<void>.delayed(Duration.zero);

    expect(aborted, isTrue);
  });

  test('http.runWithClient로 바꾼 클라이언트는 공용 풀 대신 그대로 쓴다', () async {
    final zoneClient = _RecordingTransport();
    final transport = http.runWithClient(
      PooledHttpTransport.new,
      () => zoneClient,
    );

    await transport.get(Uri.parse('https://api.test/zone'));
    transport.close();

    expect(zoneClient.requests.single.url.path, '/zone');
    expect(zoneClient.closed, isTrue);
  });
}
