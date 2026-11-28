import 'dart:convert';

import 'package:http/http.dart' as http;

import '../entities/ingredient_overlap_entity.dart';
import '../entities/patient_hash_entity.dart';
import '../services/api_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/api_response_parser.dart';

// 파일명: check_ingredient_overlap_control.dart
// 역할: 등록 결과 화면의 품목 번호로 복약 목록과 같은 성분이 있는지 서버에 한 번 확인한다.

// Class Name: CheckIngredientOverlap
// Role: Asks the server which result medicines share a main ingredient with the medication list or with each other.
// Responsibilities:
// - Send only valid, distinct product numbers (at most 50) and skip HTTP when none remain.
// - Treat a server without the route (404) as no overlap and decode the overlaps by product number.
// Attributes:
// - baseUrl (String): Base URL of the medication API.
// - patientHash (String): Ownership hash sent as a selector; the server resolves the caller's own scope.
// - _client (http.Client): HTTP transport; closed by dispose only when created here.
class CheckIngredientOverlap {
  static const int maxItemSeqs = 50;
  static final RegExp _itemSeqPattern = RegExp(r'^[0-9]{1,32}$');

  final String baseUrl;
  final String patientHash;
  final http.Client _client;
  final bool _ownsClient;

  // Function Name: CheckIngredientOverlap
  // Description: Normalizes the patient selector and binds requests to the backend and HTTP client.
  // Parameters: baseUrl (String): API base URL; patientHash (String): owner selector; client (http.Client?): injected transport.
  // Returns: CheckIngredientOverlap.
  CheckIngredientOverlap({
    this.baseUrl = ApiConfig.baseUrl,
    String patientHash = PatientHash.defaultPatientHash,
    http.Client? client,
  }) : patientHash = PatientHash.normalizePatientHash(patientHash),
       _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // Function Name: requestableItemSeqs
  // Description: Trims product numbers and keeps the distinct numeric ones the server accepts, in order.
  // Parameters: itemSeqs (Iterable<String>): product numbers of the result rows; empty values are allowed.
  // Returns: At most maxItemSeqs product numbers.
  static List<String> requestableItemSeqs(Iterable<String> itemSeqs) => {
    for (final itemSeq in itemSeqs)
      if (_itemSeqPattern.hasMatch(itemSeq.trim())) itemSeq.trim(),
  }.take(maxItemSeqs).toList(growable: false);

  // Function Name: requestIngredientOverlap
  // Description: Checks the product numbers once; no HTTP is sent when no valid number remains.
  // Parameters: itemSeqs (Iterable<String>): product numbers of the result rows.
  // Returns: Future<Map<String, List<IngredientOverlap>>> by product number; empty for 404. Other failures propagate.
  Future<Map<String, List<IngredientOverlap>>> requestIngredientOverlap(
    Iterable<String> itemSeqs,
  ) async {
    final requested = requestableItemSeqs(itemSeqs);
    if (requested.isEmpty) return const {};

    final response = await _client
        .post(
          Uri.parse('$baseUrl/ingredient-overlap'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'patient_hash': patientHash,
            'item_seqs': requested,
          }),
        )
        .timeout(const Duration(seconds: 15));
    // 경로가 없는 이전 서버는 안내 없이 넘어간다.
    if (response.statusCode == 404) return const {};

    final body = ApiResponseParser.decodeMap(
      ApiResponseParser.requireOkBody('성분 중복 확인 실패', response),
    );
    final items = body['items'];
    if (items is! List) return const {};
    final overlapsByItemSeq = <String, List<IngredientOverlap>>{};
    for (final item in items) {
      if (item is! Map) continue;
      final itemSeq = item['item_seq']?.toString().trim() ?? '';
      final overlaps = item['overlaps'];
      if (itemSeq.isEmpty || overlaps is! List) continue;
      overlapsByItemSeq[itemSeq] = List.unmodifiable(
        overlaps.map(IngredientOverlap.tryParse).whereType<IngredientOverlap>(),
      );
    }
    return Map.unmodifiable(overlapsByItemSeq);
  }

  // 함수이름: dispose
  // 함수역할: Control이 직접 생성한 HTTP Client를 정리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음.
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
