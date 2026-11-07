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



// Class Name: RequestVoiceGuide
// Role: Resolve medication voice guidance and delegate playback.
// Responsibilities: Cache text by medication content and language, fall back locally on server failure, and invalidate pending playback on stop.
// Attributes: baseUrl/_client/_ownsClient: HTTP endpoint and ownership; _ttsService/_speaker: playback boundaries; _requestGeneration: cancellation revision; _voiceGuideTextCache: resolved text by request JSON.
class RequestVoiceGuide {
  final String baseUrl;
  final TTSService? _ttsService;
  final VoiceGuideSpeaker? _speaker;
  final http.Client _client;
  final bool _ownsClient;
  // 안내 문구를 받아오는 동안 중지·화면 종료가 일어났는지 구분하는 요청 번호.
  int _requestGeneration = 0;
  final Map<String, String> _voiceGuideTextCache = {};

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
    final generation = ++_requestGeneration;
    final voiceGuideText = await _getVoiceGuideText(
      medicationDetail: medicationDetail,
      language: userSetting.language,
    );
    final normalizedVoiceGuideText = voiceGuideText.trim();
    if (generation != _requestGeneration) {
      // 문구를 기다리는 사이 중지했거나 화면을 떠났으면 뒤늦게 읽기 시작하지 않는다.
      return normalizedVoiceGuideText;
    }
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

  // Function Name: _getVoiceGuideText
  // Description: Reuse cached guidance for identical medication content and language; cache only nonblank results from the server-or-local resolver.
  // Parameters: medicationDetail (MedicationDetail): guidance source; language (String): requested language.
  // Returns: Future<String>: cached or newly resolved guidance.
  Future<String> _getVoiceGuideText({
    required MedicationDetail medicationDetail,
    required String language,
  }) async {
    final requestBody = jsonEncode(
      _buildVoiceGuideRequestBody(medicationDetail, language),
    );
    final cachedVoiceGuideText = _voiceGuideTextCache[requestBody];
    if (cachedVoiceGuideText != null) {
      return cachedVoiceGuideText;
    }
    final voiceGuideText = await _requestVoiceGuideText(
      requestBody: requestBody,
      medicationDetail: medicationDetail,
      language: language,
    );
    if (voiceGuideText.trim().isNotEmpty) {
      _voiceGuideTextCache[requestBody] = voiceGuideText;
    }
    return voiceGuideText;
  }

  // Function Name: _requestVoiceGuideText
  // Description: Request server guidance, logging any request or response failure and falling back to local medication text.
  // Parameters: requestBody (String): encoded guidance request; medicationDetail (MedicationDetail): fallback source; language (String): fallback language.
  // Returns: Future<String>: nonblank server text or local fallback.
  Future<String> _requestVoiceGuideText({
    required String requestBody,
    required MedicationDetail medicationDetail,
    required String language,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/voice-guide'),
            headers: const {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(const Duration(seconds: 15));
      final responseBody = ApiResponseParser.requireOkBody(
        'Voice guide request failed',
        response,
      );

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
    _requestGeneration += 1;
    await _ttsService?.stop();
  }

  // Function Name: dispose
  // Description: Closes the HTTP client only when this control created it; injected clients remain owned by the caller.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  void dispose() {
    _requestGeneration += 1;
    if (_ownsClient) {
      _client.close();
    }
  }
}
