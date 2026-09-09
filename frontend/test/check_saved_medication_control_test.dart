// File Name: check_saved_medication_control_test.dart
// Role: Regression coverage for patient-scoped medication persistence, duplicate results, and
//   manual/OCR fields.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/patient_hash_entity.dart';


// Function Name: main
// Description:
// - Register regression cases for patient-scoped medication persistence, duplicate results, and
//   manual/OCR fields.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: test callback
  // Description:
  // - Expected behavior: saveMedicationDetail sends patient hash and schedule fields.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('saveMedicationDetail sends patient hash and schedule fields', () async {
    late Map<String, dynamic> requestBody;
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 약 저장 POST 경로를 검사하고 JSON 본문을 기록한 뒤 저장 식별자 37을 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 저장 성공과 id 37의 HTTP 200 응답.
    final client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://localhost/save');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"success":true,"id":37}', 200);
    });
    final control = CheckSavedMedication(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    final result = await control.saveMedicationDetail(
      const MedicationDetail(
        itemSeq: '200000001',
        itemName: 'test-tablet',
        efficacy: 'effect',
        usageMethod: 'usage',
        warning: 'warning',
        interaction: 'avoid anticoagulants',
        sideEffect: 'drowsiness',
        storageMethod: 'store below 25 C',
        imageUrl: 'https://nedrug.mfds.go.kr/medicine.jpg',
      ),
      medicationSchedule: const MedicationSchedule(
        medicationName: 'test-tablet',
        prescriptionBatchId: 'batch_1234567890abcdef',
        dosage: '1 tablet',
        intakeTime: '3 times',
        medicationTime: 7,
      ),
    );

    expect(result.status, MedicationSaveStatus.saved);
    expect(result.isCompleted, isTrue);
    expect(result.savedMedicationId, 37);
    expect(requestBody['patient_hash'], 'patient-a');
    expect(requestBody['item_seq'], '200000001');
    expect(requestBody['item_name'], 'test-tablet');
    expect(requestBody['prescription_batch_id'], 'batch_1234567890abcdef');
    expect(requestBody['dosage_per_time'], '1 tablet');
    expect(requestBody['daily_frequency'], '3 times');
    expect(requestBody['total_days'], '7\uC77C');
    expect(requestBody['interaction'], 'avoid anticoagulants');
    expect(requestBody['side_effect'], 'drowsiness');
    expect(requestBody['storage_method'], 'store below 25 C');
    expect(requestBody['image_url'], 'https://nedrug.mfds.go.kr/medicine.jpg');
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 사용자가 수정한 OCR 약명을 저장 이름으로 우선한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('사용자가 수정한 OCR 약명을 저장 이름으로 우선한다', () async {
    late Map<String, dynamic> requestBody;
    // Function Name: MockClient callback
    // Description:
    // - Capture the save JSON so the corrected OCR medication name can be checked.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 acknowledging a successful save.
    final client = MockClient((http.Request request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"success":true}', 200);
    });
    final control = CheckSavedMedication(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    await control.saveMedicationDetail(
      const MedicationDetail(
        itemName: '에니코프캡슐',
        efficacy: 'effect',
        usageMethod: 'usage',
        warning: 'warning',
      ),
      medicationSchedule: const MedicationSchedule(
        medicationName: '애니코프캡슐',
        rawMedicationName: '에니코프캡슐',
        nameCorrectionSource: 'user_edit',
      ),
    );

    expect(requestBody['item_name'], '애니코프캡슐');
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 직접 등록한 약명과 복용 시간대를 저장 요청에 반영한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('직접 등록한 약명과 복용 시간대를 저장 요청에 반영한다', () async {
    late Map<String, dynamic> requestBody;
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 직접 등록 저장 본문을 기록하고 새 저장 식별자 42를 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청.
    // 반환값:
    // - 저장 성공과 id 42의 HTTP 200 응답.
    final client = MockClient((http.Request request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"success":true,"id":42}', 200);
    });
    final control = CheckSavedMedication(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    final result = await control.saveMedicationDetail(
      const MedicationDetail(
        itemName: '공공데이터 후보명',
        efficacy: '',
        usageMethod: '',
        warning: '',
      ),
      medicationSchedule: const MedicationSchedule(
        medicationName: '직접 입력한 약',
        nameCorrectionSource: 'manual_entry',
        dosage: '0.5정',
        intakeTime: '2회',
        medicationTime: 4,
        scheduleSlotKeys: ['morning', 'evening'],
      ),
    );

    expect(result.status, MedicationSaveStatus.saved);
    expect(result.savedMedicationId, 42);
    expect(requestBody['item_name'], '직접 입력한 약');
    expect(requestBody['dosage_per_time'], '0.5정');
    expect(requestBody['daily_frequency'], '2회');
    expect(requestBody['total_days'], '4일');
    expect(requestBody['schedule_slot_keys'], ['morning', 'evening']);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 약 저장 응답의 중복 여부를 신규 저장 성공과 구별하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('saveMedicationDetail reports duplicate result', () async {
    // 함수이름: MockClient 콜백
    // 함수역할:
    // - 같은 약이 이미 저장되어 신규 저장이 거절된 결과를 제공한다.
    // 매개변수:
    // - request (http.Request): 실제 서버 전송 대신 가로챈 HTTP 요청. 이 대역에서는 직접 사용하지 않는다.
    // 반환값:
    // - duplicate=true, success=false인 HTTP 200 응답.
    final client = MockClient((http.Request request) async {
      return http.Response(
        '{"success":false,"duplicate":true,"message":"이미 추가된 약입니다."}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = CheckSavedMedication(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    final result = await control.saveMedicationDetail(
      const MedicationDetail(
        itemName: 'test-tablet',
        efficacy: 'effect',
        usageMethod: 'usage',
        warning: 'warning',
      ),
    );

    expect(result.status, MedicationSaveStatus.duplicate);
    expect(result.isCompleted, isTrue);
    expect(result.message, '이미 추가된 약입니다.');
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestSavedMedicationInfo scopes list request by patient hash.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test(
    'requestSavedMedicationInfo scopes list request by patient hash',
    () async {
      // Function Name: MockClient callback
      // Description:
      // - Assert the patient-scoped saved-list request and provide full medication, dosage, image, and guide
      //   fields.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server.
      // Returns:
      // - HTTP 200 with the saved medication fixture.
      final client = MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/list');
        expect(request.url.queryParameters['patient_hash'], 'patient-a');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {
                'id': 1,
                'patient_hash': 'patient-a',
                'item_seq': '200000001',
                'item_name': 'test-tablet',
                'efficacy': 'effect',
                'use_method': 'usage',
                'warning_message': 'warning',
                'interaction': 'avoid anticoagulants',
                'side_effect': 'drowsiness',
                'storage_method': 'store below 25 C',
                'dosage_per_time': '1 tablet',
                'daily_frequency': '3 times',
                'total_days': '7 days',
                'image_url': 'https://nedrug.mfds.go.kr/medicine.jpg',
                'ai_guide': 'guide',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final control = CheckSavedMedication(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      );

      final medications = await control.requestSavedMedicationInfo();

      expect(medications, hasLength(1));
      expect(medications.first.patientHash, 'patient-a');
      expect(medications.first.itemSeq, '200000001');
      expect(medications.first.dosagePerTime, '1 tablet');
      expect(medications.first.interaction, 'avoid anticoagulants');
      expect(medications.first.sideEffect, 'drowsiness');
      expect(medications.first.storageMethod, 'store below 25 C');
      expect(
        medications.first.imageUrl,
        'https://nedrug.mfds.go.kr/medicine.jpg',
      );
    },
  );

  // Function Name: test callback
  // Description:
  // - Expected behavior: requestDelete scopes delete request by patient hash.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  test('requestDelete scopes delete request by patient hash', () async {
    // Function Name: MockClient callback
    // Description:
    // - Assert patient-scoped deletion without legacy role/user parameters and acknowledge removal.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 with a successful deletion result.
    final client = MockClient((http.Request request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/delete/3');
      expect(request.url.queryParameters['patient_hash'], 'patient-a');
      expect(request.url.queryParameters.containsKey('role'), isFalse);
      expect(request.url.queryParameters.containsKey('user_hash'), isFalse);
      return http.Response('{"success":true}', 200);
    });
    final control = CheckSavedMedication(
      baseUrl: 'http://localhost',
      patientHash: 'patient-a',
      client: client,
    );

    final success = await control.requestDelete(3);

    expect(success, isTrue);
  });

  // Function Name: test callback
  // Description:
  // - Expected behavior: default patient hash remains available before UC-6 linking.
  // Parameters:
  // - None.
  // Returns:
  // - No value; a failed expectation fails this test.
  test('default patient hash remains available before UC-6 linking', () {
    expect(PatientHash.defaultPatientHash, 'local_patient');
  });
}
