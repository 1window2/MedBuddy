import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import '../entities/user_setting_entity.dart';

// 파일명: tts_service.dart
// 역할: 휴대폰/에뮬레이터의 내장 TTS 엔진으로 약 안내 문장을 읽어준다.

// Class Name: TTSService
// Role: Play medication guidance using user-selected language and reading speed.
// Responsibilities: Coordinate playback cancellation and surface platform playback failures.
// Attributes: _flutterTts (FlutterTts): injected engine; _playbackGeneration (int): invalidates superseded requests.
class TTSService {
  final FlutterTts _flutterTts;
  int _playbackGeneration = 0;

  // 함수이름: TTSService
  // 함수역할: 주입된 음성 엔진 또는 기본 FlutterTts를 사용하도록 재생 서비스를 구성한다.
  // 매개변수:
  // - flutterTts (FlutterTts?): 실제 재생을 수행할 기기 TTS 엔진
  // 반환값:
  // - TTSService: 초기화된 인스턴스.
  TTSService({FlutterTts? flutterTts})
    : _flutterTts = flutterTts ?? FlutterTts();

  // Function Name: speak
  // Description: Trim text, stop prior speech and configure playback; skip superseded requests and reject platform errors or unsuccessful start results.
  // Parameters: text (String): speech content; userSetting (UserSetting): language and speed; onComplete (void Function()?): completion/cancellation/error or pre-playback supersession callback.
  // Returns: Future<void>: playback request completion; blank text is a no-op and platform failures propagate.
  Future<void> speak(
    String text,
    UserSetting userSetting, {
    void Function()? onComplete,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return;
    }

    // 이전 발화를 정리한 뒤 완료 시점까지 기다려 재생 상태와 실제 음성을 일치시킨다.
    final generation = ++_playbackGeneration;
    await _flutterTts.stop();
    await _flutterTts.awaitSpeakCompletion(true);
    String? platformError;
    // 플랫폼은 재생 오류 때 speak 호출을 끝내지 않으므로 오류 알림으로도 대기를 끝낼 수 있게 한다.
    final playbackResult = Completer<dynamic>();
    _flutterTts.setCompletionHandler(/* 함수이름: setCompletionHandler 콜백
     * 함수역할: 음성 재생이 정상 종료되면 호출자의 완료 콜백을 실행한다.
     * 매개변수:
     * - 없음.
     * 반환값:
     * - 없음.
     */() {
      onComplete?.call();
    });
    _flutterTts.setCancelHandler(/* 함수이름: setCancelHandler 콜백
     * 함수역할: 음성 재생 취소도 호출자의 완료 콜백으로 전달한다.
     * 매개변수:
     * - 없음.
     * 반환값:
     * - 없음.
     */() {
      onComplete?.call();
    });
    _flutterTts.setErrorHandler(/* 함수이름: setErrorHandler 콜백
     * 함수역할: 플랫폼 음성 오류 메시지를 저장하고 호출자의 완료 콜백을 실행한 뒤 대기 중인 재생 요청을 끝낸다.
     * 매개변수:
     * - message (dynamic): 사용자에게 표시하거나 오류로 보존할 안내 문구
     * 반환값:
     * - 없음.
     */(message) {
      platformError = '$message';
      onComplete?.call();
      if (!playbackResult.isCompleted) {
        playbackResult.complete(null);
      }
    });
    await _flutterTts.setLanguage(_languageCode(userSetting.language));
    await _flutterTts.setSpeechRate(_speechRate(userSetting.readingSpeed));
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    if (generation != _playbackGeneration) {
      // 준비하는 사이 중지되었거나 새 재생이 시작됐으면 뒤늦게 읽기 시작하지 않는다.
      onComplete?.call();
      return;
    }
    unawaited(
      _flutterTts
          .speak(normalizedText, focus: true)
          .then(
            /* 함수이름: then 콜백
             * 함수역할: 플랫폼 재생 요청의 결과로 대기를 끝낸다. 오류 알림이 먼저 끝냈으면 무시한다.
             * 매개변수:
             * - result (dynamic): 플랫폼이 돌려준 재생 결과
             * 반환값:
             * - 없음.
             */
            (result) {
              if (!playbackResult.isCompleted) {
                playbackResult.complete(result);
              }
            },
            /* 함수이름: onError 콜백
             * 함수역할: 플랫폼 재생 요청의 예외를 대기 중인 재생 요청에 전달한다. 오류 알림이 먼저 끝냈으면 무시한다.
             * 매개변수:
             * - error (Object): 플랫폼 호출에서 발생한 예외
             * - stackTrace (StackTrace): 예외가 발생한 호출 스택
             * 반환값:
             * - 없음.
             */
            onError: (Object error, StackTrace stackTrace) {
              if (!playbackResult.isCompleted) {
                playbackResult.completeError(error, stackTrace);
              }
            },
          ),
    );
    final result = await playbackResult.future;
    if (platformError != null) {
      throw StateError('TTS playback failed: $platformError');
    }
    if (generation != _playbackGeneration) {
      // 사용자가 중지했거나 새 재생으로 바뀐 요청은 엔진 시작 실패가 아니다.
      return;
    }
    if (result != 1 && result != true) {
      throw StateError('TTS engine did not start playback.');
    }
  }

  // Function Name: stop
  // Description: Invalidate pending playback configuration and stop the speech engine.
  // Parameters: None.
  // Returns: Future<void>: platform stop completion.
  Future<void> stop() async {
    _playbackGeneration += 1;
    await _flutterTts.stop();
  }

  // Function Name: _languageCode
  // Description: Map supported app language to a TTS locale.
  // Parameters: language (String): app language code.
  // Returns: String: en-US for English, otherwise ko-KR.
  String _languageCode(String language) {
    return isEnglishLanguage(language) ? 'en-US' : 'ko-KR';
  }

  // 함수이름: _speechRate
  // 함수역할: 사용자 읽기 배속을 느림 0.34·보통 0.50·빠름 0.66의 TTS 엔진 속도로 변환한다.
  // 매개변수:
  // - readingSpeed (double): 사용자 읽기 배속 선택값
  // 반환값:
  // - double: 사용자 읽기 배속을 느림 0.34·보통 0.50·빠름 0.66의 TTS 엔진 속도로 변환한다.
  double _speechRate(double readingSpeed) {
    if (readingSpeed < 1.0) {
      return 0.34;
    }
    if (readingSpeed > 1.0) {
      return 0.66;
    }
    return 0.50;
  }
}
