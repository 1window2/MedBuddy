import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../entities/pill_identification_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';

enum PillIdentificationFailure {
  emptyImage,
  oversizedImage,
  timedOut,
  invalidPhoto,
  serviceUnavailable,
  invalidResponse,
  fileUnreadable,
}

class PillIdentificationException implements Exception {
  final PillIdentificationFailure failure;

  const PillIdentificationException(this.failure);
}

class IdentifyPill {
  static const int maxImageBytes = 10 * 1024 * 1024;

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
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _client = client ?? http.Client(),
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
      final request = http.AbortableMultipartRequest(
        'POST',
        Uri.parse('$baseUrl/pill-identification/candidates'),
        abortTrigger: abortTrigger.future,
      )..files.add(
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
        response =
            await _client.send(request).then(http.Response.fromStream).timeout(
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
        throw PillIdentificationException(
          _failureForStatus(response.statusCode),
        );
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

  static PillIdentificationFailure _failureForStatus(int statusCode) {
    return switch (statusCode) {
      413 => PillIdentificationFailure.oversizedImage,
      422 => PillIdentificationFailure.invalidPhoto,
      503 => PillIdentificationFailure.serviceUnavailable,
      504 => PillIdentificationFailure.timedOut,
      _ => PillIdentificationFailure.invalidResponse,
    };
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
