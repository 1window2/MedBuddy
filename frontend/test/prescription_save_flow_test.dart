// 파일명: prescription_save_flow_test.dart
// 역할: 촬영 파일 입력부터 처방 검토·저장·복약함·오늘 일정 갱신까지 실제 Control을 연결해 검증한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/entities/prescription_flow_entity.dart';
import 'package:medbuddy_frontend/services/prescription_local_ocr_service.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';

// 함수이름: main
// 함수역할: 촬영·분석·저장 단계의 부분 실패, 응답 유실과 재시도 시나리오를 등록한다.
// 매개변수: 없음. 반환값: 없음.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 함수이름: setUp
  // 함수역할: 이전 시험의 사용자 설정이 다음 시험에 남지 않도록 초기화한다.
  // 매개변수: 없음. 반환값: 없음.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 함수이름: 촬영 후 등록 성공 테스트
  // 함수역할: 사진 경로 대신 비식별 텍스트만 서버에 보내고 두 약의 날짜·용량·시간대를 보존하는지 확인한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료.
  test('촬영 인식 결과가 복약함과 오늘 일정까지 반영된다', () async {
    final flow = _RegistrationFlow();
    addTearDown(flow.dispose);
    await flow.analyze();
    expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
    expect(flow.model.savedMedicationInfoList, hasLength(2));
    expect(flow.model.todayMedicationScheduleList, hasLength(2));
    expect(flow.model.todayMedicationProgress.totalCount, 4);
    expect(flow.model.todayMedicationProgress.completedCount, 0);
    expect(flow.rows.first['prescription_date'], flow.today);
    expect(flow.rows.first['prescription_batch_id'], 'registration_batch_0001');
    expect(flow.rows.first['dosage_per_time'], '0.5정');
    expect(flow.rows.first['schedule_slot_keys'], [
      'morning',
      'lunch',
      'evening',
    ]);
    expect(flow.rows.last['schedule_slot_keys'], ['morning']);
    expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
    expect(flow.saveAttempts, ['첫째 시험약', '둘째 시험약']);
  });

  // 함수이름: 개별 저장 후 전체 저장 테스트
  // 함수역할: 이미 저장한 행을 건너뛰고 나머지 약만 저장한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료.
  test('개별 저장 후 전체 저장은 남은 약만 요청한다', () async {
    final flow = _RegistrationFlow();
    addTearDown(flow.dispose);
    await flow.analyze();
    expect(
      await flow.model.requestMedicationSave(
        flow.model.analyzedMedicationList.first,
        0,
      ),
      isTrue,
    );
    expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
    expect(flow.saveAttempts, ['첫째 시험약', '둘째 시험약']);
    expect(flow.rows, hasLength(2));
  });

  for (final failBoth in [false, true]) {
    // 함수이름: 저장 실패 재시도 테스트
    // 함수역할: 부분·전체 실패 뒤 성공한 행은 유지하고 실패한 행만 재시도한다.
    // 매개변수: 없음. 반환값: 비동기 검증 완료.
    test('저장 실패 후 재시도에서 누락·중복이 없다: all=$failBoth', () async {
      final flow = _RegistrationFlow();
      addTearDown(flow.dispose);
      await flow.analyze();
      flow.failedSaves.add('둘째 시험약');
      if (failBoth) flow.failedSaves.add('첫째 시험약');
      expect(await flow.model.requestAllAnalyzedMedicationSave(), isFalse);
      expect(flow.rows, hasLength(failBoth ? 0 : 1));
      expect(
        flow.model.completedMedicationSaveIndexes,
        failBoth ? isEmpty : {0},
      );
      flow.failedSaves.clear();
      expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
      expect(flow.rows, hasLength(2));
      expect(
        flow.saveAttempts.where((name) => name == '첫째 시험약'),
        hasLength(failBoth ? 2 : 1),
      );
      expect(flow.model.todayMedicationProgress.totalCount, 4);
      expect(flow.model.isAllMedicationSaving, isFalse);
    });
  }

  // 함수이름: 저장 응답 유실 재시도 테스트
  // 함수역할: 서버에는 저장됐지만 응답이 끊긴 행을 재시도해도 같은 저장 ID를 재사용한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료.
  test('저장 응답 유실 후 재시도는 기존 저장 항목을 사용한다', () async {
    final flow = _RegistrationFlow()..loseSaveResponse = true;
    addTearDown(flow.dispose);
    await flow.analyze();
    expect(await flow.model.requestAllAnalyzedMedicationSave(), isFalse);
    expect(flow.rows, hasLength(2));
    expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
    expect(flow.rows, hasLength(2));
    expect(flow.model.completedMedicationSaveIndexes, {0, 1});
  });

  // 함수이름: 저장 이후 일정 조회 실패 테스트
  // 함수역할: 저장 성공과 일정 조회 실패를 구분하고 재조회 시 저장된 약이 보이는지 확인한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료.
  test('저장 후 일정 조회 실패는 오류로 남고 재조회로 복구된다', () async {
    final flow = _RegistrationFlow();
    addTearDown(flow.dispose);
    await flow.analyze();
    flow.failSchedule = true;
    expect(await flow.model.requestAllAnalyzedMedicationSave(), isTrue);
    expect(flow.model.hasTodayScheduleLoadError, isTrue);
    expect(flow.rows, hasLength(2));
    flow.failSchedule = false;
    await flow.model.fetchTodayMedicationSchedule();
    expect(flow.model.hasTodayScheduleLoadError, isFalse);
    expect(flow.model.todayMedicationProgress.totalCount, 4);
  });
}

// 클래스명: _RegistrationFlow
// 역할: OCR·HTTP 외부 경계만 대체하고 앱의 실제 분석·저장·조회 Control을 연결한다.
// 주요 책임: 테스트 요청을 기록하고 부분 실패·저장 응답 유실·조회 실패를 재현한다.
class _RegistrationFlow {
  late final MockClient client;
  late final MedBuddyViewModel model;
  final List<Map<String, dynamic>> rows = [];
  final List<String> saveAttempts = [];
  final Set<String> failedSaves = {};
  final String today = DateTime.now().toIso8601String().substring(0, 10);
  bool loseSaveResponse = false;
  bool failSchedule = false;

  // 함수이름: _RegistrationFlow
  // 함수역할: 실제 ViewModel과 Control을 외부 연결 없는 시험 클라이언트에 연결한다.
  // 매개변수: 없음. 반환값: 준비된 시험 흐름.
  _RegistrationFlow() {
    client = MockClient(_respond);
    model = MedBuddyViewModel(
      patientHash: 'registration-patient',
      apiClient: client,
      inputPrescription: InputPrescription(
        client: client,
        localOcrBoundary: _LocalOcr(),
      ),
    );
  }

  // 함수이름: analyze
  // 함수역할: 촬영 파일 입력 경로로 OCR 검토와 약품 분석을 수행하고 저장 가능 상태를 확인한다.
  // 매개변수: 없음. 반환값: 분석 완료 Future.
  Future<void> analyze() async {
    await model.requestCapturedPrescriptionImage(
      XFile('registration-fixture.png'),
    );
    expect(model.prescriptionFlowState, PrescriptionFlowState.previewReady);
    await model.requestPrescriptionAnalysis();
    expect(
      model.prescriptionFlowState,
      PrescriptionFlowState.analysisSucceeded,
    );
    expect(model.analyzedMedicationList, hasLength(2));
  }

  // 함수이름: _respond
  // 함수역할: API 계약에 맞는 응답을 만들고 요청별 실패를 재현한다. 외부 서버·파일은 사용하지 않는다.
  // 매개변수: request 실제 Control이 만든 요청. 반환값: 시험 응답 또는 통신 실패 예외.
  Future<http.Response> _respond(http.Request request) async {
    final path = request.url.path;
    Object response;
    if (path.endsWith('/analyze-prescription-text')) {
      expect(jsonDecode(request.body), {'text': '비식별 시험 처방 텍스트'});
      response = {
        'prescription_date': today,
        'prescription_batch_id': 'registration_batch_0001',
        'medications': [
          {
            'drug_name': '첫째 시험약',
            'dosage_per_time': '0.5정',
            'daily_frequency': '3',
            'total_days': '7',
          },
          {
            'drug_name': '둘째 시험약',
            'dosage_per_time': '1정',
            'daily_frequency': '1',
            'total_days': '7',
          },
        ],
      };
    } else if (path.endsWith('/identify')) {
      response = {
        'success': true,
        'data': [
          {
            'item_name': jsonDecode(request.body)['extracted_text'],
            'efficacy': '',
            'usage_method': '',
            'warning': '',
          },
        ],
      };
    } else if (path.endsWith('/save')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['patient_hash'], 'registration-patient');
      final name = body['item_name'] as String;
      saveAttempts.add(name);
      if (failedSaves.contains(name)) {
        return http.Response('{"detail":"temporary failure"}', 503);
      }
      final duplicate = rows
          .where((row) => row['item_name'] == name)
          .firstOrNull;
      if (duplicate != null) {
        response = {'success': false, 'duplicate': true, 'id': duplicate['id']};
      } else {
        final row = {...body, 'id': rows.length + 1};
        rows.add(row);
        if (loseSaveResponse) {
          loseSaveResponse = false;
          throw const SocketException('Simulated lost acknowledgement');
        }
        response = {'success': true, 'id': row['id']};
      }
    } else if (path.endsWith('/list') || path.endsWith('/schedule/today')) {
      expect(
        request.url.queryParameters['patient_hash'],
        'registration-patient',
      );
      response = failSchedule && path.endsWith('/schedule/today')
          ? {'success': false, 'data': []}
          : {'success': true, 'data': rows};
    } else {
      throw StateError('Unexpected test request: $path');
    }
    return http.Response(
      jsonEncode(response),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  // 함수이름: dispose
  // 함수역할: 선택 파일 정리를 기다린 뒤 시험용 ViewModel과 클라이언트를 종료한다.
  // 매개변수: 없음. 반환값: 자원 해제 완료 Future.
  Future<void> dispose() async {
    await model.inputPrescription.clearSelectedImage();
    model.dispose();
    client.close();
  }
}

// 클래스명: _LocalOcr
// 역할: 카메라·문자 인식 엔진 없이 비식별 텍스트를 제공하는 테스트 경계.
// 주요 책임: 실제 개인정보나 처방 이미지를 외부로 보내지 않고 후속 등록 경로를 시험한다.
class _LocalOcr implements PrescriptionLocalOcrBoundary {
  // 함수이름: recognizeAndMask
  // 함수역할: 주어진 촬영 파일의 인식 결과를 고정된 비식별 시험 문구로 대체한다.
  // 매개변수: imagePath 촬영 파일 식별값. 반환값: 시험 OCR 결과.
  @override
  Future<LocalPrescriptionOcrResult> recognizeAndMask(String imagePath) async =>
      const LocalPrescriptionOcrResult(
        maskedText: '비식별 시험 처방 텍스트',
        regions: [],
      );
}
