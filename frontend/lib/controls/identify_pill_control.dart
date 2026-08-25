// 파일명: identify_pill_control.dart
// 역할: 낱알약 이미지 식별 요청, 응답 변환과 결과 저장을 수행한다.

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

class PillIdentificationException implements Exception {
  final PillIdentificationFailure failure;
  final Duration? retryAfter;

  const PillIdentificationException(this.failure, {this.retryAfter});
}

class IdentifyPill {
  static const int maxImageBytes = 10 * 1024 * 1024;
  static const int maxBatchImageCount = 10;

  final String baseUrl;
  final ImagePicker _imagePicker;
  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;
  final Set<Completer<void>> _abortTriggers = <Completer<void>>{};

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

  // 함수명: requestMultiplePillImagesFromGallery
  // 역할: 서로 다른 알약을 한 장씩 촬영한 사진을 갤러리에서 여러 장 선택해 순서대로 읽는다.
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
              onTimeout: () {
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

  // 함수명: _exceptionForResponse
  // 역할: HTTP 오류와 서버가 안내한 재시도 대기시간을 손실 없이 변환한다.
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

  // 함수명: _parseRetryAfter
  // 역할: 초 단위 또는 HTTP 날짜 형식의 Retry-After 값을 안전한 대기시간으로 변환한다.
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
