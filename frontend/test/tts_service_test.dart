import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/services/tts_service.dart';

// 파일명: tts_service_test.dart
// 역할: 음성 안내 서비스가 발화 설정과 실패 결과를 정확히 처리하는지 검증한다.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TTS 재생은 완료 대기와 오디오 포커스를 활성화한다', () async {
    final flutterTts = _FakeFlutterTts();
    final service = TTSService(flutterTts: flutterTts);
    var completed = false;

    await service.speak(
      '복약 안내 문장입니다.',
      const UserSetting(readingSpeed: 1.2),
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

  test('TTS 엔진이 발화를 시작하지 못하면 오류를 반환한다', () async {
    final flutterTts = _FakeFlutterTts()..speakResult = 0;
    final service = TTSService(flutterTts: flutterTts);

    expect(
      () => service.speak('복약 안내 문장입니다.', const UserSetting()),
      throwsA(isA<StateError>()),
    );
  });
}

class _FakeFlutterTts extends FlutterTts {
  dynamic speakResult = 1;
  bool stoppedBeforeSpeaking = false;
  bool awaitCompletion = false;
  bool requestedAudioFocus = false;
  String? language;
  double? speechRate;
  String? spokenText;

  VoidCallback? _completionHandler;

  @override
  Future<dynamic> stop() async {
    stoppedBeforeSpeaking = true;
    return 1;
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    this.awaitCompletion = awaitCompletion;
    return 1;
  }

  @override
  void setCompletionHandler(VoidCallback callback) {
    _completionHandler = callback;
  }

  @override
  Future<dynamic> setLanguage(String language) async {
    this.language = language;
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    speechRate = rate;
    return 1;
  }

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spokenText = text;
    requestedAudioFocus = focus;
    if (speakResult == 1) {
      _completionHandler?.call();
    }
    return speakResult;
  }
}
