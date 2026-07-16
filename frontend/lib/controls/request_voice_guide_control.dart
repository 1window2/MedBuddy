import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_detail_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';
import '../services/tts_service.dart';

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
// - backend를 사용할 수 없는 경우 MedicationDetail의 로컬 문구로 fallback한다.
// - 실제 음성 재생은 TTS Service로 위임한다.
class RequestVoiceGuide {
  final String baseUrl;
  final TTSService? _ttsService;
  final VoiceGuideSpeaker? _speaker;
  final http.Client _client;
  final bool _ownsClient;

  RequestVoiceGuide({
    this.baseUrl = ApiConfig.baseUrl,
    TTSService? ttsService,
    VoiceGuideSpeaker? speaker,
    http.Client? client,
  })  : _ttsService = ttsService ?? (speaker == null ? TTSService() : null),
        _speaker = speaker,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  // 함수명: requestVoiceGuide
  // 함수역할:
  // - 음성 안내 문구를 생성한 뒤 사용자 설정에 맞게 TTS Service로 재생한다.
  // 매개변수:
  // - medicationDetail: 약 상세 정보와 복용 스케줄을 묶은 안내 모델
  // - userSetting: 언어와 읽기 속도 설정
  // - onComplete: 음성 안내 종료 시 호출할 콜백
  // 반환값:
  // - 실제 재생 요청에 사용한 음성 안내 문구
  Future<String> requestVoiceGuide({
    required MedicationDetail medicationDetail,
    required UserSetting userSetting,
    void Function()? onComplete,
  }) async {
    final voiceGuideText = await _getVoiceGuideText(
      medicationDetail: medicationDetail,
      language: userSetting.language,
    );
    final normalizedVoiceGuideText = voiceGuideText.trim();
    await requestTTS(
      voiceGuideText: normalizedVoiceGuideText,
      userSetting: userSetting,
      onComplete: onComplete,
    );
    return normalizedVoiceGuideText;
  }

  Future<void> requestTTS({
    required String voiceGuideText,
    required UserSetting userSetting,
    void Function()? onComplete,
  }) async {
    final normalizedVoiceGuideText = voiceGuideText.trim();
    if (normalizedVoiceGuideText.isEmpty) {
      onComplete?.call();
      throw StateError('Voice guide text is empty.');
    }
    await (_speaker ?? _ttsService!.speak)(
      normalizedVoiceGuideText,
      userSetting,
      onComplete: onComplete,
    );
  }

  // 함수명: _getVoiceGuideText
  // 함수역할:
  // - backend에서 음성 안내 문구를 가져오고 실패 시 로컬 문구를 반환한다.
  // 매개변수:
  // - medicationDetail: 약 상세 정보와 복용 스케줄을 묶은 안내 모델
  // - language: 사용자 언어 설정
  // 반환값:
  // - 음성 안내 문구
  Future<String> _getVoiceGuideText({
    required MedicationDetail medicationDetail,
    required String language,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/voice-guide'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(
              _buildVoiceGuideRequestBody(medicationDetail, language),
            ),
          )
          .timeout(const Duration(seconds: 15));
      final responseBody = ApiResponseParser.decodeBody(response);

      if (response.statusCode != 200) {
        throw StateError(
          'Voice guide request failed (${response.statusCode}): '
          '${ApiResponseParser.extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = ApiResponseParser.decodeMap(responseBody);
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
      return medicationDetail.voiceGuideText;
    }
  }

  Map<String, dynamic> _buildVoiceGuideRequestBody(
    MedicationDetail medicationDetail,
    String language,
  ) {
    return {
      'item_name': medicationDetail.itemName,
      'usage_method': medicationDetail.usageMethod,
      'warning': medicationDetail.warning,
      'language': language,
    };
  }

  Future<void> stop() async {
    await _ttsService?.stop();
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
