// 파일명: medication_history_fixtures.dart
// 역할: 복약 이력 전용 테스트에 개인정보 없는 응답과 고정 시각을 제공한다.
import 'dart:convert';

import 'package:http/http.dart' as http;

final historyTestNow = DateTime.utc(2026, 10, 17, 6);

// 함수역할: 지정 날짜·약·상태를 이력 응답 한 건으로 만든다. 반환값은 변경 가능한 테스트 맵이다.
Map<String, dynamic> historyTestEntry({
  int id = 1,
  String name = '테스트 주간약',
  String date = '2026-10-16',
  String slot = 'morning',
  String status = 'unrecorded',
  int revision = 0,
  String mode = 'scheduled',
}) => {
  'medication_id': id,
  'item_name': name,
  'schedule_date': date,
  'slot_key': slot,
  'status': status,
  'revision': revision,
  'dosing_mode': mode,
  'actual_taken_at': null,
  'recorded_at': null,
  'reason': '',
};

// 함수역할: 기간과 선택적 기록 목록을 GET 계약 형식으로 묶고 필요시 복용 약을 포함한다.
Map<String, dynamic> historyTestBody({
  String start = '2026-10-11',
  String end = '2026-10-17',
  List<Map<String, dynamic>>? items,
}) => {
  'items': items ?? [historyTestEntry()],
  'start_date': start,
  'end_date': end,
  'medications': [
    {
      'id': 1,
      'item_name': '테스트 주간약',
      'dosing_mode': 'scheduled',
      'daily_frequency': '주 1회',
      'dosage_per_time': '1정',
    },
    {
      'id': 2,
      'item_name': '테스트 필요시약',
      'dosing_mode': 'as_needed',
      'dosage_per_time': '1정',
    },
  ],
};

// 함수역할: 테스트 JSON과 상태 코드를 UTF-8 HTTP 응답으로 바꾼다.
http.Response historyTestResponse(Object body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
