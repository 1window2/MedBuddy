import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../entities/medication_schedule_entity.dart';
import '../services/api_config.dart';

class InputPrescription {
  final String baseUrl;
  final ImagePicker _imagePicker;
  final http.Client _client;
  final bool _ownsClient;

  InputPrescription({
    this.baseUrl = ApiConfig.baseUrl,
    ImagePicker? imagePicker,
    http.Client? client,
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  Future<List<MedicationSchedule>?> requestPrescriptionImage() async {
    return _requestPrescriptionImage(ImageSource.camera);
  }

  Future<List<MedicationSchedule>?>
      requestPrescriptionImageFromGallery() async {
    return _requestPrescriptionImage(ImageSource.gallery);
  }

  Future<List<MedicationSchedule>?> _requestPrescriptionImage(
    ImageSource imageSource,
  ) async {
    final image = await _imagePicker.pickImage(
      source: imageSource,
      imageQuality: 82,
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
    if (image == null) {
      return null;
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/upload-prescription'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      final streamedResponse = await _client.send(request).timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw StateError('처방전 분석 요청 시간이 초과되었습니다.');
        },
      );
      final response = await http.Response.fromStream(streamedResponse);
      final responseBody = utf8.decode(response.bodyBytes);

      if (response.statusCode != 200) {
        throw StateError(
          '분석 실패 (${response.statusCode}): ${_extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = _decodeMap(responseBody);
      final rawMedications = decodedData['medications'];
      if (rawMedications is! List) {
        return [];
      }

      return rawMedications
          .whereType<Map>()
          .map(
            (item) => MedicationSchedule.fromAnalysisJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false);
    } on StateError {
      rethrow;
    } on FileSystemException catch (error, stackTrace) {
      developer.log(
        'Prescription image file access failed.',
        name: 'InputPrescription',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError(_imageFileAccessErrorMessage(imageSource));
    } catch (error, stackTrace) {
      developer.log(
        'Prescription image upload failed.',
        name: 'InputPrescription',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('서버 연결에 실패했습니다.');
    }
  }

  Map<String, dynamic> _decodeMap(String responseBody) {
    final dynamic decodedData = jsonDecode(responseBody);
    if (decodedData is Map<String, dynamic>) {
      return decodedData;
    }
    throw StateError('서버 응답 형식이 올바르지 않습니다.');
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

  String _imageFileAccessErrorMessage(ImageSource imageSource) {
    return imageSource == ImageSource.gallery
        ? '선택한 이미지 파일을 읽을 수 없습니다.'
        : '촬영한 이미지 파일을 읽을 수 없습니다.';
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
