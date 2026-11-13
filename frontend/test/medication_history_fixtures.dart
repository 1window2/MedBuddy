// 파일명: medication_history_fixtures.dart
// 역할: 복약 이력 전용 테스트에 개인정보 없는 응답과 고정 시각을 제공한다.
import 'dart:convert';

import 'package:http/http.dart' as http;

final historyTestNow = DateTime.utc(2026, 10, 17, 6);

// 함수이름: historyTestEntry
// 함수역할:
// - 지정한 약·날짜·상태를 이력 조회 응답 한 건으로 만들며 기록 시각은 미지정 상태로 둔다.
// 매개변수:
// - id(int): 약 식별자; 기본값은 1이다.
// - name(String): 화면 표시용 가상 약 이름.
// - date(String): 이력이 속한 yyyy-MM-dd 날짜.
// - slot(String): 복용 시간대 키; 기본값은 morning이다.
// - status(String): 복용 기록 상태; 기본값은 unrecorded이다.
// - revision(int): 충돌 검증에 사용하는 기록 버전.
// - mode(String): scheduled 또는 필요시 복용 모드.
// 반환값:
// - Map<String, dynamic>: 실제 기록 시각이 null이고 사유가 빈, 수정 가능한 응답 맵.
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

// 함수이름: historyTestBody
// 함수역할:
// - 조회 기간과 기록 목록을 GET 응답 계약으로 묶고 정기·필요시 약의 가상 목록을 포함한다.
// 매개변수:
// - start(String): 조회 시작일; 기본값은 2026-10-11이다.
// - end(String): 조회 종료일; 기본값은 2026-10-17이다.
// - items(List<Map<String, dynamic>>?): 사용할 기록 목록; null일 때만 기본 이력 한 건을 만든다.
// 반환값:
// - Map<String, dynamic>: 기간, 기록, 약 두 종류를 포함하는 응답 맵; 입력 날짜는 검증하지 않는다.
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

// 함수이름: historyTestResponse
// 함수역할:
// - 한글 약 이름을 보존하도록 JSON을 UTF-8 바이트로 인코딩해 HTTP 응답을 만든다.
// 매개변수:
// - body(Object): JSON으로 인코딩할 응답 본문.
// - status(int): HTTP 상태 코드; 기본값은 200이다.
// 반환값:
// - http.Response: JSON 콘텐츠 형식을 가진 응답; 인코딩 불가능한 본문은 오류를 발생시킨다.
http.Response historyTestResponse(Object body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
