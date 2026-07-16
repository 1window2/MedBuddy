import 'dart:developer' as developer;
import 'dart:io';

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

  Future<XFile?> requestPillImage(ImageSource source) {
    return _imagePicker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
  }

  Future<PillIdentificationResult> requestPillIdentification({
    required XFile frontImage,
    XFile? backImage,
  }) async {
    try {
      final frontBytes = await _readBoundedImage(frontImage);
      final backBytes =
          backImage == null ? null : await _readBoundedImage(backImage);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/pill-identification/candidates'),
      )..files.add(
          http.MultipartFile.fromBytes(
            'front',
            frontBytes,
            filename: 'pill-front.jpg',
          ),
        );
      if (backBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'back',
            backBytes,
            filename: 'pill-back.jpg',
          ),
        );
      }

      final response =
          await _client.send(request).then(http.Response.fromStream).timeout(
                requestTimeout,
                onTimeout: () => throw const PillIdentificationException(
                  PillIdentificationFailure.timedOut,
                ),
              );
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
    } on FileSystemException catch (error) {
      developer.log(
        'Pill image file access failed: ${error.runtimeType}.',
        name: 'IdentifyPill',
      );
      throw const PillIdentificationException(
        PillIdentificationFailure.fileUnreadable,
      );
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

  Future<List<int>> _readBoundedImage(XFile image) async {
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
    return bytes;
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
    if (_ownsClient) {
      _client.close();
    }
  }
}
