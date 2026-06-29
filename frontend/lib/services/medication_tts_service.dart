import 'package:flutter_tts/flutter_tts.dart';

import '../entities/user_setting_entity.dart';

// 파일명: medication_tts_service.dart
// 역할: 휴대폰/에뮬레이터의 내장 TTS 엔진으로 약 안내 문장을 읽어준다.

// 클래스명: MedicationTtsService
// 역할: Flutter TTS 플러그인을 감싸 사용자 설정과 음성 안내 호출을 분리한다.
// 주요 책임:
// - 사용자 언어와 읽기 속도를 TTS 엔진 설정으로 변환한다.
// - 상세정보 화면에서 재생/정지 요청을 단순한 메서드로 제공한다.
class MedicationTtsService {
  final FlutterTts _flutterTts;

  MedicationTtsService({
    FlutterTts? flutterTts,
  }) : _flutterTts = flutterTts ?? FlutterTts();

  // 함수명: speak
  // 함수역할:
  // - 전달받은 문장을 사용자 설정에 맞는 언어와 속도로 읽는다.
  // 매개변수:
  // - text: 읽을 안내 문장
  // - userSetting: 언어와 읽기 속도 설정
  // - onComplete: 읽기가 끝났을 때 호출할 콜백
  // 반환값:
  // - 없음
  Future<void> speak(
    String text,
    UserSetting userSetting, {
    void Function()? onComplete,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return;
    }

    _flutterTts.setCompletionHandler(() {
      onComplete?.call();
    });
    _flutterTts.setCancelHandler(() {
      onComplete?.call();
    });
    await _flutterTts.setLanguage(_languageCode(userSetting.language));
    await _flutterTts.setSpeechRate(_speechRate(userSetting.readingSpeed));
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.speak(normalizedText);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  String _languageCode(String language) {
    return language == 'en' ? 'en-US' : 'ko-KR';
  }

  double _speechRate(double readingSpeed) {
    if (readingSpeed < 1.0) {
      return 0.38;
    }
    if (readingSpeed > 1.0) {
      return 0.58;
    }
    return 0.48;
  }
}
