import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../entities/medication_schedule_entity.dart';
import '../services/api_config.dart';

typedef PrescriptionImageSelectedCallback = void Function();

// 파일명: input_prescription_control.dart
// 역할: 카메라와 갤러리에서 처방전 이미지를 받아 백엔드 OCR API로 전송한다.

// 클래스명: InputPrescription
// 역할: 처방전 이미지 선택, 업로드, OCR 결과 변환을 담당한다.
// 주요 책임:
// - 카메라 또는 갤러리에서 이미지를 선택한다.
// - 이미지가 실제 선택된 뒤에만 진행 상태 콜백을 호출한다.
// - 백엔드 OCR 응답을 MedicationSchedule 목록으로 변환한다.
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

  // 함수명: requestPrescriptionImage
  // 함수역할:
  // - 카메라로 처방전 이미지를 촬영하고 OCR 분석을 요청한다.
  // 매개변수:
  // - onImageSelected: 이미지 선택 직후 진행 상태로 전환하는 콜백
  // 반환값:
  // - OCR에서 추출한 복약 일정 목록, 취소 시 null
  Future<List<MedicationSchedule>?> requestPrescriptionImage({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    return _requestPrescriptionImage(
      ImageSource.camera,
      onImageSelected: onImageSelected,
    );
  }

  // 함수명: requestPrescriptionImageFromGallery
  // 함수역할:
  // - 갤러리에서 처방전 이미지를 선택하고 OCR 분석을 요청한다.
  // 매개변수:
  // - onImageSelected: 이미지 선택 직후 진행 상태로 전환하는 콜백
  // 반환값:
  // - OCR에서 추출한 복약 일정 목록, 취소 시 null
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    return _requestPrescriptionImage(
      ImageSource.gallery,
      onImageSelected: onImageSelected,
    );
  }

  // 함수명: _requestPrescriptionImage
  // 함수역할:
  // - 이미지 소스별 공통 OCR 업로드 흐름을 처리한다.
  // - 백엔드가 반환한 조제일자를 각 약 일정에 함께 실어 보존한다.
  // 매개변수:
  // - imageSource: 카메라 또는 갤러리 이미지 소스
  // - onImageSelected: 이미지 선택 완료 후 실행할 콜백
  // 반환값:
  // - OCR에서 추출한 복약 일정 목록, 취소 시 null
  Future<List<MedicationSchedule>?> _requestPrescriptionImage(
    ImageSource imageSource, {
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
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
    onImageSelected?.call();

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
      final prescriptionDate =
          decodedData['prescription_date']?.toString().trim() ?? '';
      final rawMedications = decodedData['medications'];
      if (rawMedications is! List) {
        return [];
      }

      return rawMedications
          .whereType<Map>()
          .map((item) {
            final itemJson = Map<String, dynamic>.from(item);
            itemJson.putIfAbsent('prescription_date', () => prescriptionDate);
            return MedicationSchedule.fromAnalysisJson(itemJson);
          })
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
