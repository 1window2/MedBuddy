// 파일명: device_speech_engine_test.dart
// 역할: 기기 TTS 채널이 MainActivity와 약속한 메서드·인자로 요청하고 재생 결과 알림을 처리기에 전달하는지 검증한다.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/device_speech_engine.dart';

// 함수이름: main
// 함수역할:
// - TTS 채널 요청 형식과 완료·취소·오류 알림 전달 사례를 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/device_speech_engine');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 재생·중지·설정 요청은 네이티브가 처리하는 이름과 인자로 전달된다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('요청은 네이티브 TTS 채널의 메서드 이름과 인자로 전달된다', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 1;
    });
    final engine = DeviceSpeechEngine.forChannel(channel);

    await engine.stop();
    await engine.setLanguage('ko-KR');
    await engine.setSpeechRate(0.5);
    await engine.setVolume(1.0);
    await engine.setPitch(1.0);
    expect(await engine.speak('안내 문장', focus: true), 1);

    expect(calls.map((call) => call.method), [
      'stop',
      'setLanguage',
      'setSpeechRate',
      'setVolume',
      'setPitch',
      'speak',
    ]);
    expect(calls[1].arguments, 'ko-KR');
    expect(calls[2].arguments, 0.5);
    expect(calls.last.arguments, {'text': '안내 문장', 'focus': true});
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 네이티브의 완료·취소·오류 알림은 등록된 처리기를 호출한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('재생 결과 알림은 등록된 처리기로 전달된다', () async {
    final engine = DeviceSpeechEngine.forChannel(channel);
    final events = <String>[];
    engine.setCompletionHandler(() => events.add('complete'));
    engine.setCancelHandler(() => events.add('cancel'));
    engine.setErrorHandler((message) => events.add('error:$message'));

    for (final call in const [
      MethodCall('onComplete'),
      MethodCall('onCancel'),
      MethodCall('onError', 'Error from TextToSpeech (speak) - -3'),
    ]) {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(call),
        (_) {},
      );
    }

    expect(events, [
      'complete',
      'cancel',
      'error:Error from TextToSpeech (speak) - -3',
    ]);
  });
}
