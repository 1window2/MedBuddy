import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_guide_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/api_config.dart';
import '../services/medication_tts_service.dart';

typedef VoiceGuideSpeaker = Future<void> Function(
  String text,
  UserSetting userSetting, {
  void Function()? onComplete,
});

// 파일명: request_voice_guide_control.dart
// 역할: 음성 안내 문구 요청과 TTS Service 호출을 조정한다.

// 클래스명: RequestVoiceGuide
// 역할: 약 상세 정보 기반 음성 안내 요청을 처리한다.
// 주요 책임:
// - backend RequestVoiceGuide control에서 음성 안내 문구를 받아온다.
// - backend를 사용할 수 없는 경우 MedicationGuide의 로컬 문구로 fallback한다.
// - 실제 음성 재생은 TTS Service로 위임한다.
class RequestVoiceGuide {
  final String baseUrl;
  final MedicationTtsService? _ttsService;
  final VoiceGuideSpeaker? _speaker;
  final http.Client _client;
  final bool _ownsClient;

  RequestVoiceGuide({
    this.baseUrl = ApiConfig.baseUrl,
    MedicationTtsService? ttsService,
    VoiceGuideSpeaker? speaker,
    http.Client? client,
  })  : _ttsService =
            ttsService ?? (speaker == null ? MedicationTtsService() : null),
        _speaker = speaker,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  // 함수명: requestVoiceGuide
  // 함수역할:
  // - 음성 안내 문구를 생성한 뒤 사용자 설정에 맞게 TTS Service로 재생한다.
  // 매개변수:
  // - medicationGuide: 약 상세 정보와 복용 스케줄을 묶은 안내 모델
  // - userSetting: 언어와 읽기 속도 설정
  // - onComplete: 음성 안내 종료 시 호출할 콜백
  // 반환값:
  // - 실제 재생 요청에 사용한 음성 안내 문구
  Future<String> requestVoiceGuide({
    required MedicationGuide medicationGuide,
    required UserSetting userSetting,
    void Function()? onComplete,
  }) async {
    final voiceGuideText = await getVoiceGuideText(
      medicationGuide: medicationGuide,
      language: userSetting.language,
    );
    await (_speaker ?? _ttsService!.speak)(
      voiceGuideText,
      userSetting,
      onComplete: onComplete,
    );
    return voiceGuideText;
  }

  // 함수명: getVoiceGuideText
  // 함수역할:
  // - backend에서 음성 안내 문구를 가져오고 실패 시 로컬 문구를 반환한다.
  // 매개변수:
  // - medicationGuide: 약 상세 정보와 복용 스케줄을 묶은 안내 모델
  // - language: 사용자 언어 설정
  // 반환값:
  // - 음성 안내 문구
  Future<String> getVoiceGuideText({
    required MedicationGuide medicationGuide,
    required String language,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/voice-guide'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'item_name': medicationGuide.itemName,
              'efficacy': medicationGuide.efficacy,
              'usage_method': medicationGuide.usageMethod,
              'warning': medicationGuide.warning,
              'dosage_per_time': medicationGuide.dosagePerTime,
              'daily_frequency': medicationGuide.dailyFrequency,
              'total_days': medicationGuide.totalDays,
              'language': language,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final responseBody = utf8.decode(response.bodyBytes);

      if (response.statusCode != 200) {
        throw StateError(
          'Voice guide request failed (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = _decodeMap(responseBody);
      final rawData = decodedData['data'];
      if (rawData is Map && rawData['voice_guide_text'] != null) {
        final voiceGuideText = rawData['voice_guide_text'].toString().trim();
        if (voiceGuideText.isNotEmpty) {
          return voiceGuideText;
        }
      }
      throw StateError('Server response did not include voice guide text.');
    } catch (error, stackTrace) {
      developer.log(
        'Voice guide request fell back to local guide text.',
        name: 'RequestVoiceGuide',
        error: error,
        stackTrace: stackTrace,
      );
      return medicationGuide.voiceGuideText;
    }
  }

  Future<void> stop() async {
    await _ttsService?.stop();
  }

  Map<String, dynamic> _decodeMap(String responseBody) {
    final dynamic decodedData = jsonDecode(responseBody);
    if (decodedData is Map<String, dynamic>) {
      return decodedData;
    }
    throw StateError('Server response format was invalid.');
  }

  String _extractErrorDetail(String responseBody) {
    try {
      final decodedError = _decodeMap(responseBody);
      if (decodedError['detail'] != null) {
        return decodedError['detail'].toString();
      }
    } catch (_) {
      return responseBody;
    }
    return responseBody;
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
