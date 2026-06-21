import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../entities/patient_caregiver_link_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';

// 파일명: link_patient_caregiver_control.dart
// 역할: 환자-보호자 연동 API와 프론트 화면을 연결한다.

// 클래스명: LinkPatientCaregiver
// 역할: 환자 코드 생성, 보호자 등록, 연동 해제를 처리한다.
// 주요 책임:
// - 현재 사용자 해시 기준의 연동 목록을 조회한다.
// - 환자 측 임시 연동 코드를 생성한다.
// - 보호자 측에서 환자 코드를 등록하거나 기존 연동을 해제한다.
class LinkPatientCaregiver {
  final String baseUrl;
  final String userHash;
  final http.Client _client;
  final bool _ownsClient;

  LinkPatientCaregiver({
    this.baseUrl = ApiConfig.baseUrl,
    this.userHash = PatientHash.defaultPatientHash,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  // 함수명: requestPatientCaregiverLink
  // 함수역할:
  // - 클래스 다이어그램의 기존 메서드명을 유지하기 위한 연동 목록 조회 wrapper이다.
  // 반환값:
  // - 현재 사용자 해시 기준 활성 연동 목록
  Future<List<PatientCaregiverLink>> requestPatientCaregiverLink() {
    return requestLinkPage();
  }

  // 함수명: requestLinkPage
  // 함수역할:
  // - 현재 사용자 해시 기준으로 활성 환자-보호자 연동 목록을 조회한다.
  // 반환값:
  // - 활성 환자-보호자 연동 목록
  Future<List<PatientCaregiverLink>> requestLinkPage() async {
    try {
      final response = await _client
          .get(_buildLinkUri('link/list'))
          .timeout(const Duration(seconds: 30));
      final responseBody = utf8.decode(response.bodyBytes);

      if (response.statusCode != 200) {
        throw StateError(
          'Link lookup failed (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = _decodeMap(responseBody);
      return _decodeLinkList(decodedData['data']);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Patient-caregiver link lookup failed.',
        name: 'LinkPatientCaregiver',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Link lookup failed.');
    }
  }

  // 함수명: requestPatientCode
  // 함수역할:
  // - 보호자 등록에 사용할 환자 임시 코드를 요청한다.
  // 반환값:
  // - 서버가 생성한 환자 코드
  Future<String> requestPatientCode() async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/link/code'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'patient_hash': userHash}),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = utf8.decode(response.bodyBytes);

      if (response.statusCode != 200) {
        throw StateError(
          'Patient code creation failed (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      final decodedData = _decodeMap(responseBody);
      final rawData = decodedData['data'];
      if (rawData is Map) {
        return (rawData['patient_code'] ?? '').toString();
      }
      throw StateError('Server response did not include a patient code.');
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Patient code request failed.',
        name: 'LinkPatientCaregiver',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Patient code creation failed.');
    }
  }

  // 함수명: registerPatientCode
  // 함수역할:
  // - 현재 보호자 해시를 환자 코드와 연결한다.
  // 매개변수:
  // - patientCode: 환자가 생성한 임시 코드
  // 반환값:
  // - 생성된 환자-보호자 연동 정보
  Future<PatientCaregiverLink> registerPatientCode(String patientCode) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/link/register'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'caregiver_hash': userHash,
              'patient_code': patientCode,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final responseBody = utf8.decode(response.bodyBytes);

      if (response.statusCode != 200) {
        throw StateError(
          'Patient registration failed (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      return _decodeSingleLink(_decodeMap(responseBody)['data']);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Patient registration failed.',
        name: 'LinkPatientCaregiver',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Patient registration failed.');
    }
  }

  // 함수명: requestUnlink
  // 함수역할:
  // - 현재 사용자 해시 기준으로 환자-보호자 연동 하나를 해제한다.
  // 매개변수:
  // - linkId: 환자-보호자 연동 식별자
  // 반환값:
  // - 해제 처리된 환자-보호자 연동 정보
  Future<PatientCaregiverLink> requestUnlink(int linkId) async {
    try {
      final response = await _client
          .delete(_buildLinkUri('link/$linkId'))
          .timeout(const Duration(seconds: 30));
      final responseBody = utf8.decode(response.bodyBytes);

      if (response.statusCode != 200) {
        throw StateError(
          'Unlink failed (${response.statusCode}): '
          '${_extractErrorDetail(responseBody)}',
        );
      }

      return _decodeSingleLink(_decodeMap(responseBody)['data']);
    } on StateError {
      rethrow;
    } catch (error, stackTrace) {
      developer.log(
        'Patient-caregiver unlink failed.',
        name: 'LinkPatientCaregiver',
        error: error,
        stackTrace: stackTrace,
      );
      throw StateError('Unlink failed.');
    }
  }

  PatientCaregiverLink _decodeSingleLink(dynamic rawItem) {
    if (rawItem is Map) {
      return PatientCaregiverLink.fromJson(Map<String, dynamic>.from(rawItem));
    }
    throw StateError('Server response did not include a link.');
  }

  List<PatientCaregiverLink> _decodeLinkList(dynamic rawItems) {
    if (rawItems is! List) {
      return [];
    }

    return rawItems
        .whereType<Map>()
        .map((item) =>
            PatientCaregiverLink.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
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

  Uri _buildLinkUri(String path) {
    return Uri.parse('$baseUrl/$path').replace(
      queryParameters: {'user_hash': userHash},
    );
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
