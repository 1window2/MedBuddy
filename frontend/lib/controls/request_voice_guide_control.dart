// File Name: request_voice_guide_control.dart
// Role: Retrieves medication voice-guide text with local fallback and coordinates device speech playback.

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/medication_detail_entity.dart';
import '../entities/user_setting_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';
import '../services/tts_service.dart';

// Function Name: VoiceGuideSpeaker
// Description: Defines asynchronous speech playback using guide text and user settings, with an optional completion callback.
// Parameters:
// - text (String): Text to recognize, normalize, redact, or speak.
// - userSetting (UserSetting): User settings including language, accessibility, and notification policy.
// - onComplete (void Function()?): Receiver called when speech completes or is canceled.
// Returns:
// - Future<void>: asynchronous completion without a result payload.
typedef VoiceGuideSpeaker =
    Future<void> Function(
      String text,
      UserSetting userSetting, {
      void Function()? onComplete,
    });



// 클래스명: RequestVoiceGuide
// 역할: 약 상세 정보 기반 음성 안내 요청을 처리한다.
// 주요 책임:
// - backend RequestVoiceGuide control에서 음성 안내 문구를 받아온다.
// - backend를 사용할 수 없는 경우 MedicationDetail의 로컬 문구로 fallback한다.
// - 실제 음성 재생은 TTS Service로 위임한다.
// 속성:
// - baseUrl (String): 복약 API 기본 주소
// - _ttsService (TTSService?): 사용자 설정 기반 음성 재생 서비스
// - _speaker (VoiceGuideSpeaker?): TTS 재생을 대체할 주입 가능한 음성 경계
// - _client (http.Client): 요청에 사용할 HTTP 클라이언트; 주입 여부에 따른 소유권은 생성자 설명 참조
class RequestVoiceGuide {
  final String baseUrl;
  final TTSService? _ttsService;
  final VoiceGuideSpeaker? _speaker;
  final http.Client _client;
  final bool _ownsClient;

  // Function Name: RequestVoiceGuide
  // Description: Connects voice-guide requests to HTTP and selects an injected speaker or TTS service while tracking ownership of a created client.
  // Parameters:
  // - baseUrl (String): Base URL of the medication API.
  // - ttsService (TTSService?): Speech service applying user playback settings.
  // - speaker (VoiceGuideSpeaker?): Injectable speech boundary replacing direct TTS playback.
  // - client (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // Returns:
  // - RequestVoiceGuide: the initialized instance.
  RequestVoiceGuide({
    this.baseUrl = ApiConfig.baseUrl,
    TTSService? ttsService,
    VoiceGuideSpeaker? speaker,
    http.Client? client,
  }) : _ttsService = ttsService ?? (speaker == null ? TTSService() : null),
       _speaker = speaker,
       _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // Function Name: requestVoiceGuide
  // Description: Obtains guide text for the medication and preferred language, trims it, and requests speech using the user's reading settings and completion callback.
  // Parameters:
  // - medicationDetail (MedicationDetail): Medication detail record associated with the course.
  // - userSetting (UserSetting): User settings including language, accessibility, and notification policy.
  // - onComplete (void Function()?): Receiver called when speech completes or is canceled.
  // Returns:
  // - Future<String>: Obtains guide text for the medication and preferred language, trims it, and requests speech using the user's reading settings and completion callback.
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

  // Function Name: requestTTS
  // Description: Rejects blank guide text after signaling completion; otherwise passes trimmed text and user settings to the injected speaker or TTS service.
  // Parameters:
  // - voiceGuideText (String): Medication guidance text submitted for speech playback.
  // - userSetting (UserSetting): User settings including language, accessibility, and notification policy.
  // - onComplete (void Function()?): Receiver called when speech completes or is canceled.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
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

  // 함수이름: _getVoiceGuideText
  // 함수역할: backend에서 음성 안내 문구를 가져오고 실패 시 로컬 문구를 반환한다.
  // 매개변수:
  // - medicationDetail (MedicationDetail): 약 상세 정보와 복용 스케줄을 묶은 안내 모델
  // - language (String): 사용자 언어 설정
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
      return medicationDetail.voiceGuideTextForLanguage(language);
    }
  }

  // Function Name: _buildVoiceGuideRequestBody
  // Description: Serializes medication name, usage instructions, warnings, and the requested language for the voice-guide endpoint.
  // Parameters:
  // - medicationDetail (MedicationDetail): Medication detail record associated with the course.
  // - language (String): Language code used for display or speech guidance.
  // Returns:
  // - Map<String, dynamic>: Serializes medication name, usage instructions, warnings, and the requested language for the voice-guide endpoint.
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

  // Function Name: stop
  // Description: Stops playback on the owned TTS service when that service is present.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>: asynchronous completion without a result payload.
  Future<void> stop() async {
    await _ttsService?.stop();
  }

  // Function Name: dispose
  // Description: Closes the HTTP client only when this control created it; injected clients remain owned by the caller.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
