import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import '../entities/user_setting_entity.dart';

// 파일명: tts_service.dart
// 역할: 휴대폰/에뮬레이터의 내장 TTS 엔진으로 약 안내 문장을 읽어준다.

// 클래스명: TTSService
// 역할: Flutter TTS 플러그인을 감싸 사용자 설정과 음성 안내 호출을 분리한다.
// 주요 책임:
// - 사용자 언어와 읽기 속도를 TTS 엔진 설정으로 변환한다.
// - 상세정보 화면에서 재생/정지 요청을 단순한 메서드로 제공한다.
// - 플랫폼 음성 오류와 사용자의 중지를 구분해 대기 중인 재생 요청을 끝낸다.
// 속성:
// - _flutterTts (FlutterTts): 실제 재생을 수행할 기기 TTS 엔진
// - _playbackGeneration (int): 새 재생이나 중지가 요청될 때마다 늘어나 이전 재생 요청이 취소되었는지 알려 주는 번호
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

  // 함수이름: speak
  // 함수역할: 전달받은 문장을 사용자 설정에 맞는 언어와 속도로 읽는다. 플랫폼이 재생 오류를 알리면 기다리지 않고 StateError로 끝내며, 재생 중 중지되거나 새 재생으로 바뀐 요청은 오류 없이 끝낸다.
  // 매개변수:
  // - text (String): 읽을 안내 문장
  // - userSetting (UserSetting): 언어와 읽기 속도 설정
  // - onComplete (void Function()?): 읽기가 끝났거나 취소·오류로 멈췄을 때 호출할 콜백
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future. 엔진이 재생을 시작하지 못했거나 재생 오류를 알리면 StateError.
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

  // 함수이름: stop
  // 함수역할: 현재 음성 읽기를 플랫폼 TTS 엔진에서 중지한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>: 별도의 결과 데이터 없이 비동기 완료를 알리는 Future.
  Future<void> stop() async {
    _playbackGeneration += 1;
    await _flutterTts.stop();
  }

  // 함수이름: _languageCode
  // 함수역할: 앱 공통 기준으로 영어인 언어를 en-US로, 그 외 언어를 ko-KR 음성 로케일로 변환한다.
  // 매개변수:
  // - language (String): 표시·음성 안내에 사용할 언어 코드
  // 반환값:
  // - String: 앱 공통 기준으로 영어인 언어를 en-US로, 그 외 언어를 ko-KR 음성 로케일로 변환한다.
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
