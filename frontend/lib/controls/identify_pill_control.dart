// File Name: identify_pill_control.dart
// Role: Selects bounded pill images and submits abortable single-pill or multi-pill identification requests.

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../entities/pill_identification_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';

// 클래스명: PillIdentificationFailure
// 역할: 알약 사진 선택·검증·식별 중 발생할 수 있는 실패 원인을 구분한다.
// 주요 책임:
// - 화면 안내와 재시도 여부가 파일 오류, 호출 제한, 시간 초과와 서버 오류를 구별하게 한다.
enum PillIdentificationFailure {
  emptyImage,
  oversizedImage,
  timedOut,
  invalidPhoto,
  rateLimited,
  serviceUnavailable,
  invalidResponse,
  fileUnreadable,
}

// 클래스명: PillIdentificationException
// 역할: 알약 식별 실패 종류와 서버의 선택적 재시도 지연을 전달한다.
// 주요 책임:
// - 오류 메시지와 일괄 처리 재시도 정책에서 필요한 실패 정보를 보존한다.
// 속성:
// - failure (PillIdentificationFailure): 화면 복구 안내를 선택할 실패 분류
// - retryAfter (Duration?): 호출 제한 뒤 서버가 제안하거나 제한한 대기시간
class PillIdentificationException implements Exception {
  final PillIdentificationFailure failure;
  final Duration? retryAfter;

  // 함수이름: PillIdentificationException
  // 함수역할: 사진·서버 실패 종류와 선택적인 Retry-After 지연을 함께 보존한다.
  // 매개변수:
  // - failure (PillIdentificationFailure): 화면 복구 안내를 선택할 실패 분류
  // - retryAfter (Duration?): 호출 제한 뒤 서버가 제안하거나 제한한 대기시간
  // 반환값:
  // - PillIdentificationException: 초기화된 인스턴스.
  const PillIdentificationException(this.failure, {this.retryAfter});
}

// Class Name: IdentifyPill
// Role: Owns image selection and bounded multipart requests for pill identification.
// Responsibilities:
// - Validate image size, cancel timed-out requests, decode candidates, and preserve rate-limit retry information.
// Attributes:
// - baseUrl (String): Base URL of the medication API.
// - _imagePicker (ImagePicker): Camera and gallery image-selection boundary.
// - _client (http.Client): HTTP transport; constructor documentation specifies ownership for injected clients.
// - requestTimeout (Duration): Maximum wait for an identification or analysis request.
class IdentifyPill {
  static const int maxImageBytes = 10 * 1024 * 1024;
  static const int maxBatchImageCount = 10;

  final String baseUrl;
  final ImagePicker _imagePicker;
  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;
  final Set<Completer<void>> _abortTriggers = <Completer<void>>{};

  // Function Name: IdentifyPill
  // Description: Binds the picker and HTTP client, records client ownership, and rejects a nonpositive identification timeout.
  // Parameters:
  // - baseUrl (String): Base URL of the medication API.
  // - imagePicker (ImagePicker?): Camera and gallery image-selection boundary.
  // - client (http.Client?): HTTP transport; constructor documentation specifies ownership for injected clients.
  // - requestTimeout (Duration): Maximum wait for an identification or analysis request.
  // Returns:
  // - IdentifyPill: the initialized instance.
  IdentifyPill({
    this.baseUrl = ApiConfig.baseUrl,
    ImagePicker? imagePicker,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 45),
  }) : _imagePicker = imagePicker ?? ImagePicker(),
       _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be positive',
      );
    }
  }

  // Function Name: requestPillImage
  // Description: Selects a camera or gallery image with bounded dimensions and reads validated bytes, returning null when selection is canceled.
  // Parameters:
  // - source (ImageSource): Camera or gallery source for image selection.
  // Returns:
  // - Future<Uint8List?>: Selects a camera or gallery image with bounded dimensions and reads validated bytes, returning null when selection is canceled.
  Future<Uint8List?> requestPillImage(ImageSource source) async {
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
        requestFullMetadata: false,
      );
      return image == null ? null : await _readBoundedImage(image);
    } on PillIdentificationException {
      rethrow;
    } on FileSystemException catch (error) {
      developer.log(
        'Pill image file access failed: ${error.runtimeType}.',
        name: 'IdentifyPill',
      );
      throw const PillIdentificationException(
        PillIdentificationFailure.fileUnreadable,
      );
    }
  }

  // 함수이름: requestMultiplePillImagesFromGallery
  // 함수역할: 서로 다른 알약을 한 장씩 촬영한 사진을 갤러리에서 여러 장 선택해 순서대로 읽는다.
  // 매개변수:
  // - limit (int): 한 번에 선택하거나 조회할 최대 항목 수
  // 반환값:
  // - Future<List<Uint8List>>: 서로 다른 알약을 한 장씩 촬영한 사진을 갤러리에서 여러 장 선택해 순서대로 읽는다.
  Future<List<Uint8List>> requestMultiplePillImagesFromGallery({
    int limit = maxBatchImageCount,
  }) async {
    if (limit < 1 || limit > maxBatchImageCount) {
      throw ArgumentError.value(
        limit,
        'limit',
        'must be between 1 and $maxBatchImageCount',
      );
    }
    try {
      final images = await _imagePicker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
        limit: limit,
        requestFullMetadata: false,
      );
      final imageBytes = <Uint8List>[];
      for (final image in images) {
        imageBytes.add(await _readBoundedImage(image));
      }
      return List<Uint8List>.unmodifiable(imageBytes);
    } on PillIdentificationException {
      rethrow;
    } on FileSystemException catch (error) {
      developer.log(
        'Pill image file access failed: ${error.runtimeType}.',
        name: 'IdentifyPill',
      );
      throw const PillIdentificationException(
        PillIdentificationFailure.fileUnreadable,
      );
    }
  }

  // Function Name: requestPillIdentification
  // Description: Validates front and optional back images, sends an abortable multipart request, and decodes candidates while classifying timeout, response, and service failures.
  // Parameters:
  // - frontImage (Uint8List): Required image bytes of the pill's front side.
  // - backImage (Uint8List?): Optional image bytes of the same pill's back side.
  // Returns:
  // - Future<PillIdentificationResult>: Validates front and optional back images, sends an abortable multipart request, and decodes candidates while classifying timeout, response, and service failures.
  Future<PillIdentificationResult> requestPillIdentification({
    required Uint8List frontImage,
    Uint8List? backImage,
  }) async {
    try {
      _validateImageBytes(frontImage);
      if (backImage != null) {
        _validateImageBytes(backImage);
      }
      final abortTrigger = Completer<void>();
      _abortTriggers.add(abortTrigger);
      final request =
          http.AbortableMultipartRequest(
              'POST',
              Uri.parse('$baseUrl/pill-identification/candidates'),
              abortTrigger: abortTrigger.future,
            )
            ..files.add(
              http.MultipartFile.fromBytes(
                'front',
                frontImage,
                filename: 'pill-front.jpg',
              ),
            );
      if (backImage != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'back',
            backImage,
            filename: 'pill-back.jpg',
          ),
        );
      }

      late final http.Response response;
      try {
        response = await _client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(
              requestTimeout,
              onTimeout: /* Function Name: onTimeout callback
               * Description: Signals request abortion once and reports the pill-identification timeout.
               * Parameters:
               * - None.
               * Returns:
               * - Never returns normally; throws the timed-out identification exception.
               */() {
                if (!abortTrigger.isCompleted) {
                  abortTrigger.complete();
                }
                throw const PillIdentificationException(
                  PillIdentificationFailure.timedOut,
                );
              },
            );
      } finally {
        _abortTriggers.remove(abortTrigger);
      }
      if (response.statusCode != 200) {
        throw _exceptionForResponse(response);
      }
      final responseBody = ApiResponseParser.decodeBody(response);
      return PillIdentificationResult.fromJson(
        ApiResponseParser.decodeMap(responseBody),
      );
    } on PillIdentificationException {
      rethrow;
    } on FormatException catch (error) {
      developer.log(
        'Pill identification response parsing failed: ${error.runtimeType}.',
        name: 'IdentifyPill',
      );
      throw const PillIdentificationException(
        PillIdentificationFailure.invalidResponse,
      );
    } on StateError catch (error) {
      developer.log(
        'Pill identification response validation failed: ${error.runtimeType}.',
        name: 'IdentifyPill',
      );
      throw const PillIdentificationException(
        PillIdentificationFailure.invalidResponse,
      );
    } catch (error) {
      developer.log(
        'Pill identification request failed: ${error.runtimeType}.',
        name: 'IdentifyPill',
      );
      throw const PillIdentificationException(
        PillIdentificationFailure.serviceUnavailable,
      );
    }
  }

  // Function Name: requestMultiplePillIdentification
  // Description: Uploads one validated photo and decodes spatially separated pill groups, aborting the request on timeout and translating malformed or unavailable responses.
  // Parameters:
  // - image (Uint8List): Encoded bytes of the pill image to identify.
  // Returns:
  // - Future<MultiplePillIdentificationResult>: Uploads one validated photo and decodes spatially separated pill groups, aborting the request on timeout and translating malformed or unavailable responses.
  Future<MultiplePillIdentificationResult> requestMultiplePillIdentification({
    required Uint8List image,
  }) async {
    try {
      _validateImageBytes(image);
      final abortTrigger = Completer<void>();
      _abortTriggers.add(abortTrigger);
      final request =
          http.AbortableMultipartRequest(
              'POST',
              Uri.parse('$baseUrl/pill-identification/multiple-candidates'),
              abortTrigger: abortTrigger.future,
            )
            ..files.add(
              http.MultipartFile.fromBytes(
                'image',
                image,
                filename: 'multiple-pills.jpg',
              ),
            );
      late final http.Response response;
      try {
        response = await _client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(
              requestTimeout,
              onTimeout: /* Function Name: onTimeout callback
               * Description: Aborts the pending batch-identification request once and reports a timeout.
               * Parameters:
               * - None.
               * Returns:
               * - Never returns normally; throws the timed-out identification exception.
               */() {
                if (!abortTrigger.isCompleted) {
                  abortTrigger.complete();
                }
                throw const PillIdentificationException(
                  PillIdentificationFailure.timedOut,
                );
              },
            );
      } finally {
        _abortTriggers.remove(abortTrigger);
      }
      if (response.statusCode != 200) {
        throw _exceptionForResponse(response);
      }
      final responseBody = ApiResponseParser.decodeBody(response);
      return MultiplePillIdentificationResult.fromJson(
        ApiResponseParser.decodeMap(responseBody),
      );
    } on PillIdentificationException {
      rethrow;
    } on FormatException catch (error) {
      developer.log(
        'Multiple-pill response parsing failed: ${error.runtimeType}.',
        name: 'IdentifyPill',
      );
      throw const PillIdentificationException(
        PillIdentificationFailure.invalidResponse,
      );
    } catch (error) {
      developer.log(
        'Multiple-pill request failed: ${error.runtimeType}.',
        name: 'IdentifyPill',
      );
      throw const PillIdentificationException(
        PillIdentificationFailure.serviceUnavailable,
      );
    }
  }

  // Function Name: _readBoundedImage
  // Description: Checks file length before reading and validates the loaded bytes so empty or oversized images never reach the identification API.
  // Parameters:
  // - image (XFile): Local image file selected or captured by the user.
  // Returns:
  // - Future<Uint8List>: Checks file length before reading and validates the loaded bytes so empty or oversized images never reach the identification API.
  Future<Uint8List> _readBoundedImage(XFile image) async {
    final imageLength = await image.length();
    if (imageLength == 0) {
      throw const PillIdentificationException(
        PillIdentificationFailure.emptyImage,
      );
    }
    if (imageLength > maxImageBytes) {
      throw const PillIdentificationException(
        PillIdentificationFailure.oversizedImage,
      );
    }
    final bytes = await image.readAsBytes();
    _validateImageBytes(bytes);
    return bytes;
  }

  // Function Name: _validateImageBytes
  // Description: Rejects empty image data and payloads larger than the 10 MiB upload limit.
  // Parameters:
  // - bytes (Uint8List): Image bytes to inspect or validate.
  // Returns:
  // - No return value.
  void _validateImageBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const PillIdentificationException(
        PillIdentificationFailure.emptyImage,
      );
    }
    if (bytes.length > maxImageBytes) {
      throw const PillIdentificationException(
        PillIdentificationFailure.oversizedImage,
      );
    }
  }

  // 함수이름: _exceptionForResponse
  // 함수역할: HTTP 오류와 서버가 안내한 재시도 대기시간을 손실 없이 변환한다.
  // 매개변수:
  // - response (http.Response): 상태 코드와 본문을 해석할 HTTP 응답
  // 반환값:
  // - PillIdentificationException: HTTP 오류와 서버가 안내한 재시도 대기시간을 손실 없이 변환한다.
  static PillIdentificationException _exceptionForResponse(
    http.Response response,
  ) {
    final statusCode = response.statusCode;
    if (statusCode == 413) {
      return const PillIdentificationException(
        PillIdentificationFailure.oversizedImage,
      );
    }
    if (statusCode == 422) {
      return const PillIdentificationException(
        PillIdentificationFailure.invalidPhoto,
      );
    }
    if (statusCode == 408 || statusCode == 504) {
      return const PillIdentificationException(
        PillIdentificationFailure.timedOut,
      );
    }
    if (statusCode == 429) {
      return PillIdentificationException(
        PillIdentificationFailure.rateLimited,
        retryAfter: _parseRetryAfter(response.headers['retry-after']),
      );
    }
    if (statusCode >= 500 && statusCode < 600) {
      return const PillIdentificationException(
        PillIdentificationFailure.serviceUnavailable,
      );
    }
    return const PillIdentificationException(
      PillIdentificationFailure.invalidResponse,
    );
  }

  // 함수이름: _parseRetryAfter
  // 함수역할: 초 단위 또는 HTTP 날짜 형식의 Retry-After 값을 안전한 대기시간으로 변환한다.
  // 매개변수:
  // - rawValue (String?): 서버 Retry-After 헤더 원문
  // 반환값:
  // - Duration?: 초 단위 또는 HTTP 날짜 형식의 Retry-After 값을 안전한 대기시간으로 변환한다.
  static Duration? _parseRetryAfter(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final seconds = int.tryParse(value);
    if (seconds != null) {
      return Duration(seconds: seconds < 1 ? 1 : seconds);
    }
    try {
      final retryAt = HttpDate.parse(value).toUtc();
      final difference = retryAt.difference(DateTime.now().toUtc());
      return difference > Duration.zero
          ? difference
          : const Duration(seconds: 1);
    } on FormatException {
      return null;
    }
  }

  // Function Name: dispose
  // Description: Aborts every outstanding identification request and closes the HTTP client only when this control created it.
  // Parameters:
  // - None.
  // Returns:
  // - No return value.
  void dispose() {
    for (final abortTrigger in _abortTriggers) {
      if (!abortTrigger.isCompleted) {
        abortTrigger.complete();
      }
    }
    _abortTriggers.clear();
    if (_ownsClient) {
      _client.close();
    }
  }
}
