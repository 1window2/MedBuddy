// 파일명: photo_dose_control.dart
// 역할: 사진으로 복용 기록의 계획·기록 API를 호출한다. 사진은 보내지 않고, 알약 분석 결과에서
//   후보 품목과 각인 일치, 관찰한 모양·색만 보낸다.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../entities/photo_dose_plan_entity.dart';
import '../entities/pill_identification_entity.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';
import '../services/authenticated_api_client.dart';

final RegExp _label = RegExp(r'^[a-z_]{1,32}$');
final RegExp _itemSeq = RegExp(r'^[0-9A-Za-z]{1,32}$');
final RegExp _imprintCharacter = RegExp(r'[0-9A-Za-z가-힣]');

// 함수이름: photoDosePillJson
// 함수역할: 알약 분석 결과 하나를 계획 요청의 알약 값으로 바꾼다. 서버 형식에 맞지 않는 라벨과
//   품목 번호는 버린다(하나 때문에 요청 전체가 거절되지 않게).
// 매개변수: index (int): 알약 번호(1부터); result (PillIdentificationResult): 분석 결과.
// 반환값: JSON map.
Map<String, dynamic> photoDosePillJson(
  int index,
  PillIdentificationResult result,
) {
  final candidates = [
    for (final candidate in result.candidates)
      if (_itemSeq.hasMatch(candidate.itemSeq)) candidate,
  ];
  final features = result.observedFeatures;
  final imprint = '${features.frontImprint}${features.backImprint}';
  return {
    'index': index,
    'item_seqs': [
      for (final seq in {for (final c in candidates) c.itemSeq}) seq,
    ].take(100).toList(),
    'imprint_item_seqs': [
      for (final seq in {
        for (final c in candidates)
          if (c.matchedAttributes.contains('imprint')) c.itemSeq,
      })
        seq,
    ].take(100).toList(),
    'has_imprint': _imprintCharacter.allMatches(imprint).length >= 2,
    'shape': _label.hasMatch(features.shape) ? features.shape : 'unknown',
    'colors': [
      for (final color in {...features.colors})
        if (_label.hasMatch(color)) color,
    ].take(4).toList(),
  };
}

// 클래스명: PhotoDoseAnswer
// 역할: 알약 하나에 대한 사용자의 답. medicationId가 null이면 "아니에요/모르겠어요"다.
class PhotoDoseAnswer {
  final int index;
  final int? medicationId;

  const PhotoDoseAnswer(this.index, this.medicationId);

  Map<String, dynamic> toJson() => {
    'index': index,
    'medication_id': medicationId,
  };
}

// 클래스명: PhotoDoseControl
// 역할: 계획과 기록 요청을 보낸다.
// 속성: baseUrl: API 주소; requestTimeout: 요청 제한 시간.
class PhotoDoseControl {
  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;

  // 함수이름: PhotoDoseControl
  // 함수역할: 인증된 API 클라이언트를 준비한다.
  // 매개변수: baseUrl, client, requestTimeout: 주입 가능한 설정.
  // 반환값: PhotoDoseControl.
  PhotoDoseControl({
    this.baseUrl = ApiConfig.baseUrl,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _client = client ?? AuthenticatedApiClient(),
       _ownsClient = client == null;

  // 함수이름: plan
  // 함수역할: 계획을 요청한다. 첫 요청은 토큰 없이, 이후 요청은 받은 토큰과 답을 함께 보낸다.
  // 매개변수: pills: 알약 값; answers: 답; planToken: 이전 계획의 토큰.
  // 반환값: PhotoDosePlan. HTTP 실패는 ApiRequestException(409는 사진을 다시 찍어야 함).
  Future<PhotoDosePlan> plan({
    required List<Map<String, dynamic>> pills,
    List<PhotoDoseAnswer> answers = const [],
    String? planToken,
  }) async {
    final body = await _post('plan', {
      'pills': pills,
      'answers': [for (final answer in answers) answer.toJson()],
      'plan_token': ?planToken,
    });
    return PhotoDosePlan.fromJson(body);
  }

  // 함수이름: confirm
  // 함수역할: 화면에 보여준 계획대로 기록을 요청한다. 같은 작업 ID를 다시 보내면 처음 결과를 받는다.
  // 매개변수: pills, answers: 계획 입력; plan: 화면에 보여준 계획; operationId: 확인 화면마다 한 번 만든 UUID.
  // 반환값: PhotoDoseRecordResult. 계획이 바뀌었으면 409 ApiRequestException.
  Future<PhotoDoseRecordResult> confirm({
    required List<Map<String, dynamic>> pills,
    required List<PhotoDoseAnswer> answers,
    required PhotoDosePlan plan,
    required String operationId,
  }) async {
    final body = await _post('confirm', {
      'pills': pills,
      'answers': [for (final answer in answers) answer.toJson()],
      'plan_token': plan.planToken,
      'operation_id': operationId,
      'expected': plan.write,
    });
    return PhotoDoseRecordResult.fromJson(body);
  }

  // 함수이름: _post
  // 함수역할: JSON 요청을 보내고 200 응답 본문을 읽는다.
  // 매개변수: path: plan 또는 confirm; payload: 본문.
  // 반환값: 응답 map. 실패는 ApiRequestException.
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) {
    const operation = 'Photo dose request failed';
    return ApiResponseParser.guardRequest(
      operation: operation,
      logName: 'PhotoDoseControl',
      logMessage: 'Photo dose $path request failed.',
      request: () async {
        final response = await _client
            .post(
              Uri.parse('$baseUrl/schedule/photo-intake/$path'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(requestTimeout);
        return ApiResponseParser.decodeMap(
          ApiResponseParser.requireOkBody(operation, response),
        );
      },
    );
  }

  // 함수이름: dispose
  // 함수역할: 직접 만든 클라이언트를 닫는다.
  // 매개변수: 없음. 반환값: 없음.
  void dispose() {
    if (_ownsClient) _client.close();
  }
}
