// 파일명: tts_service_test.dart
// 역할: 음성 안내 서비스가 발화 설정과 실패 결과를 정확히 처리하는지 검증한다.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/tts_service.dart';


// 함수이름: main
// 함수역할:
// - TTS 완료 대기, 오디오 포커스, 읽기 속도와 엔진 시작 실패 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: TTS 재생은 완료 대기와 오디오 포커스를 활성화한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('TTS 재생은 완료 대기와 오디오 포커스를 활성화한다', () async {
    final flutterTts = _FakeFlutterTts();
    final service = TTSService(flutterTts: flutterTts);
    var completed = false;

    await service.speak(
      '복약 안내 문장입니다.',
      const UserSetting(readingSpeed: 1.2),
      // 함수이름: onComplete 콜백
      // 함수역할:
      // - 음성 재생 완료 안내 요청을 기록해 해당 사용자 명령의 전달 여부를 검사한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 없음; 기록 또는 상태 변경을 마친다.
      onComplete: () => completed = true,
    );

    expect(flutterTts.stoppedBeforeSpeaking, isTrue);
    expect(flutterTts.awaitCompletion, isTrue);
    expect(flutterTts.language, 'ko-KR');
    expect(flutterTts.speechRate, 0.66);
    expect(flutterTts.spokenText, '복약 안내 문장입니다.');
    expect(flutterTts.requestedAudioFocus, isTrue);
    expect(completed, isTrue);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 읽기 속도 세 단계는 알아듣기 쉬운 범위에서 충분한 간격을 유지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('읽기 속도 세 단계는 알아듣기 쉬운 범위에서 충분한 간격을 유지한다', () async {
    const speedCases = <(double, double)>[
      (0.8, 0.34),
      (1.0, 0.50),
      (1.2, 0.66),
    ];

    for (final speedCase in speedCases) {
      final flutterTts = _FakeFlutterTts();
      final service = TTSService(flutterTts: flutterTts);

      await service.speak(
        '복약 안내 문장입니다.',
        UserSetting(readingSpeed: speedCase.$1),
      );

      expect(flutterTts.speechRate, speedCase.$2);
    }
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: TTS 엔진이 발화를 시작하지 못하면 오류를 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('TTS 엔진이 발화를 시작하지 못하면 오류를 반환한다', () async {
    final flutterTts = _FakeFlutterTts()..speakResult = 0;
    final service = TTSService(flutterTts: flutterTts);

    expect(
      // 함수이름: expect 콜백
      // 함수역할:
      // - 발화 시작 실패를 반환하는 엔진으로 음성 안내를 요청한다.
      // 매개변수:
      // - 없음.
      // 반환값:
      // - 발화 시작 실패 예외로 완료되는 Future.
      () => service.speak('복약 안내 문장입니다.', const UserSetting()),
      throwsA(isA<StateError>()),
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 재생 중 플랫폼이 오류를 알리면 플랫폼의 재생 요청이 끝나지 않아도 완료 콜백을 실행하고 오류로 끝낸다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('재생 중 플랫폼 오류는 기다리지 않고 완료 콜백과 오류로 끝낸다', () async {
    final flutterTts = _FakeFlutterTts()..holdSpeak = true;
    final service = TTSService(flutterTts: flutterTts);
    var completedCount = 0;

    final speaking = service.speak(
      '복약 안내 문장입니다.',
      const UserSetting(),
      // 함수역할: 완료 안내 횟수를 센다. 매개변수: 없음. 반환값: 없음.
      onComplete: () => completedCount += 1,
    );
    await pumpEventQueue();
    expect(flutterTts.spokenText, '복약 안내 문장입니다.');
    expect(completedCount, 0);

    flutterTts.reportError('synthesis failed');

    await expectLater(
      speaking.timeout(const Duration(seconds: 1)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'TTS playback failed: synthesis failed',
        ),
      ),
    );
    expect(completedCount, 1);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 재생 중 사용자가 중지하면 엔진 시작 실패가 아니라 정상 취소로 끝낸다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('재생 중 중지는 엔진 시작 실패가 아니라 취소로 끝난다', () async {
    final flutterTts = _FakeFlutterTts()..holdSpeak = true;
    final service = TTSService(flutterTts: flutterTts);
    var completedCount = 0;

    final speaking = service.speak(
      '복약 안내 문장입니다.',
      const UserSetting(),
      // 함수역할: 완료 안내 횟수를 센다. 매개변수: 없음. 반환값: 없음.
      onComplete: () => completedCount += 1,
    );
    await pumpEventQueue();
    expect(flutterTts.spokenText, '복약 안내 문장입니다.');

    await service.stop();

    await speaking.timeout(const Duration(seconds: 1));
    expect(completedCount, 1);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 음성 설정을 준비하는 사이 중지하면 뒤늦게 읽기 시작하지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('준비 중 중지한 재생은 뒤늦게 시작하지 않는다', () async {
    final flutterTts = _FakeFlutterTts();
    final service = TTSService(flutterTts: flutterTts);
    var completedCount = 0;

    final speaking = service.speak(
      '복약 안내 문장입니다.',
      const UserSetting(),
      // 함수역할: 완료 안내 횟수를 센다. 매개변수: 없음. 반환값: 없음.
      onComplete: () => completedCount += 1,
    );
    await service.stop();
    await speaking;

    expect(flutterTts.spokenText, isNull);
    expect(completedCount, 1);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 대소문자나 지역 코드가 붙은 영어 설정도 영어 음성 로케일을 사용한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('영어 설정은 영어 음성 로케일로 읽는다', () async {
    final flutterTts = _FakeFlutterTts();
    final service = TTSService(flutterTts: flutterTts);

    await service.speak(
      'Medication guide.',
      const UserSetting(language: 'en-US'),
    );

    expect(flutterTts.language, 'en-US');
  });
}

// 클래스명: _FakeFlutterTts
// 역할: 음성 출력 없이 발화 설정, 완료 콜백과 엔진 결과를 기록하는 TTS 대역.
// 주요 책임:
// - 이전 발화를 먼저 중지했는지 기록하고 엔진 성공 값을 제공한다.
// - 발화 완료 대기 옵션을 기록하고 설정 성공 값을 제공한다.
// - 성공한 모의 발화가 호출할 완료 처리기를 보관한다.
// - 요청하면 발화를 끝내지 않고 붙잡아 재생 중 오류와 중지를 재현한다.
// 속성:
// - awaitCompletion (bool): 엔진 발화 완료까지 대기할지 여부.
// - language (String?): 화면 문구 또는 알림 내용의 언어 코드.
// - holdSpeak (bool): 발화 요청을 중지될 때까지 끝내지 않을지 여부.
class _FakeFlutterTts extends FlutterTts {
  dynamic speakResult = 1;
  bool holdSpeak = false;
  bool stoppedBeforeSpeaking = false;
  bool awaitCompletion = false;
  bool requestedAudioFocus = false;
  String? language;
  double? speechRate;
  String? spokenText;

  VoidCallback? _completionHandler;
  VoidCallback? _cancelHandler;
  ErrorHandler? _errorHandler;
  Completer<dynamic>? _pendingSpeak;

  // 함수이름: stop
  // 함수역할:
  // - 이전 발화를 먼저 중지했는지 기록하고 엔진 성공 값을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 중지 성공을 나타내는 1.
  @override
  Future<dynamic> stop() async {
    stoppedBeforeSpeaking = true;
    // 실제 플랫폼처럼 붙잡힌 발화 요청을 0으로 끝내고 취소를 알린다.
    final pendingSpeak = _pendingSpeak;
    if (pendingSpeak != null) {
      _pendingSpeak = null;
      pendingSpeak.complete(0);
      _cancelHandler?.call();
    }
    return 1;
  }

  // 함수이름: setCancelHandler
  // 함수역할:
  // - 중지된 모의 발화가 호출할 취소 처리기를 보관한다.
  // 매개변수:
  // - callback (VoidCallback): 음성 엔진 대역에 보관할 취소 처리기.
  // 반환값:
  // - 없음; 취소 콜백이 교체된다.
  @override
  void setCancelHandler(VoidCallback callback) {
    _cancelHandler = callback;
  }

  // 함수이름: setErrorHandler
  // 함수역할:
  // - 모의 재생 오류가 호출할 오류 처리기를 보관한다.
  // 매개변수:
  // - handler (ErrorHandler): 음성 엔진 대역에 보관할 오류 처리기.
  // 반환값:
  // - 없음; 오류 콜백이 교체된다.
  @override
  void setErrorHandler(ErrorHandler handler) {
    _errorHandler = handler;
  }

  // 함수이름: reportError
  // 함수역할:
  // - 실제 플랫폼처럼 발화 요청은 끝내지 않은 채 재생 오류만 알린다.
  // 매개변수:
  // - message (String): 플랫폼이 전달하는 오류 문구.
  // 반환값:
  // - 없음; 보관된 오류 처리기가 실행된다.
  void reportError(String message) {
    _errorHandler?.call(message);
  }

  // 함수이름: awaitSpeakCompletion
  // 함수역할:
  // - 발화 완료 대기 옵션을 기록하고 설정 성공 값을 제공한다.
  // 매개변수:
  // - awaitCompletion (bool): 엔진 발화 완료까지 대기할지 여부.
  // 반환값:
  // - 설정 성공을 나타내는 1.
  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    this.awaitCompletion = awaitCompletion;
    return 1;
  }

  // 함수이름: setCompletionHandler
  // 함수역할:
  // - 성공한 모의 발화가 호출할 완료 처리기를 보관한다.
  // 매개변수:
  // - callback (VoidCallback): 음성 엔진 대역에 보관할 완료 처리기.
  // 반환값:
  // - 없음; 완료 콜백이 교체된다.
  @override
  void setCompletionHandler(VoidCallback callback) {
    _completionHandler = callback;
  }

  // 함수이름: setLanguage
  // 함수역할:
  // - TTS 언어 설정 요청을 기록해 선택 언어 전달을 검사한다.
  // 매개변수:
  // - language (String): 화면 문구 또는 알림 내용의 언어 코드.
  // 반환값:
  // - 설정 성공을 나타내는 1.
  @override
  Future<dynamic> setLanguage(String language) async {
    this.language = language;
    return 1;
  }

  // 함수이름: setSpeechRate
  // 함수역할:
  // - 엔진에 전달된 읽기 속도를 기록해 옵션별 간격을 검사한다.
  // 매개변수:
  // - rate (double): 사용자 설정에서 변환한 엔진 읽기 속도.
  // 반환값:
  // - 설정 성공을 나타내는 1.
  @override
  Future<dynamic> setSpeechRate(double rate) async {
    speechRate = rate;
    return 1;
  }

  // 함수이름: setVolume
  // 함수역할:
  // - 실제 오디오 설정 없이 음량 설정 성공을 재현한다.
  // 매개변수:
  // - volume (double): 가짜 음성 엔진이 전달받는 요청 음량. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 설정 성공을 나타내는 1.
  @override
  Future<dynamic> setVolume(double volume) async => 1;

  // 함수이름: setPitch
  // 함수역할:
  // - 실제 오디오 설정 없이 음높이 설정 성공을 재현한다.
  // 매개변수:
  // - pitch (double): 가짜 음성 엔진이 전달받는 요청 음높이. 이 대역에서는 직접 사용하지 않는다.
  // 반환값:
  // - 설정 성공을 나타내는 1.
  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  // 함수이름: speak
  // 함수역할:
  // - 발화 문장과 오디오 포커스를 기록하고 성공 결과일 때만 완료 콜백을 호출한다. 붙잡도록 설정하면 중지될 때까지 끝나지 않는다.
  // 매개변수:
  // - text (String): 모의 재생에 전달한 음성 안내 문장.
  // - focus (bool): 음성 요청이 오디오 포커스를 요구하는지 여부.
  // 반환값:
  // - 테스트가 지정한 엔진 발화 결과 값.
  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spokenText = text;
    requestedAudioFocus = focus;
    if (holdSpeak) {
      final pendingSpeak = Completer<dynamic>();
      _pendingSpeak = pendingSpeak;
      return pendingSpeak.future;
    }
    if (speakResult == 1) {
      _completionHandler?.call();
    }
    return speakResult;
  }
}
