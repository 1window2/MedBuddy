// 파일명: prescription_schedule_registration_test.dart
// 역할: OCR 검토에서 수정한 복용 횟수와 시간대가 저장 요청까지 일치하는지 검증한다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/prescription_analysis_preview_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/controls/check_schedule_control.dart';
import 'package:medbuddy_frontend/controls/check_today_medication_info_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 함수이름: main
// 함수역할: 횟수 수정·시간대 직접 선택·기존 선택 보존의 등록 검증을 실행한다.
// 매개변수: 없음. 반환값: 없음.
void main() {
  // 함수이름: 정상 빈 일정 조회 테스트
  // 함수역할: 실제로 일정이 없는 성공 응답은 오류 없이 빈 목록으로 처리하는지 확인한다.
  // 매개변수: 없음. 반환값: 세 조회 경계의 비동기 검증 완료.
  test('정상 빈 일정은 성공으로 처리한다', () async {
    final client = MockClient(
      (_) async => http.Response('{"success":true,"data":[]}', 200),
    );
    addTearDown(client.close);
    final schedule = CheckSchedule(client: client);
    final summary = CheckTodayMedicationInfo(client: client);
    expect(await schedule.requestTodayMedicationSchedule(), isEmpty);
    expect(await schedule.requestMedicationScheduleWindow(), isEmpty);
    expect(await summary.requestTodayMedicationInfo(), isEmpty);
  });

  for (final key in ['schedules', 'schedule']) {
    // 함수이름: 요약 응답의 빈 일정 조회 테스트
    // 함수역할: 현재·기존 요약 응답 안의 정상 빈 목록을 오류로 오인하지 않는지 확인한다.
    // 매개변수: 없음. 반환값: 비동기 검증 완료.
    test('정상 요약 응답의 $key 목록을 읽는다', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {key: []},
          }),
          200,
        ),
      );
      addTearDown(client.close);
      expect(
        await CheckTodayMedicationInfo(
          client: client,
        ).requestTodayMedicationInfo(),
        isEmpty,
      );
    });
  }

  for (final body in [
    {'success': false, 'data': []},
    {'success': true},
    {'success': true, 'data': null},
    {'success': true, 'data': <String, dynamic>{}},
  ]) {
    // 함수이름: 저장 후 일정 조회 응답 검증
    // 함수역할: 실패하거나 목록이 없는 응답을 복약 일정 없음으로 오인하지 않도록 한다.
    // 매개변수: 없음. 반환값: 세 조회 경계의 비동기 검증 완료.
    test('잘못된 일정 조회는 빈 일정 성공으로 처리하지 않는다: $body', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(body), 200),
      );
      addTearDown(client.close);
      final schedule = CheckSchedule(client: client);
      final summary = CheckTodayMedicationInfo(client: client);
      await expectLater(
        schedule.requestTodayMedicationSchedule(),
        throwsStateError,
      );
      await expectLater(
        schedule.requestMedicationScheduleWindow(),
        throwsStateError,
      );
      await expectLater(summary.requestTodayMedicationInfo(), throwsStateError);
    });
  }

  for (final input in ['', '0', '-1', '1.5', '5', '모름']) {
    // 함수이름: 잘못된 횟수 적용 차단 테스트
    // 함수역할: 해석할 수 없는 횟수가 이전 시간대와 함께 조용히 저장되지 않는지 검증한다.
    // 매개변수: tester 화면 시험 도구. 반환값: 비동기 검증 완료.
    testWidgets('OCR 잘못된 횟수 "$input"는 적용되지 않는다', (tester) async {
      MedicationSchedule? edited;
      await _openEditor(tester, onChanged: (value) => edited = value);
      await tester.enterText(
        find.byKey(const Key('ocr-edit-frequency')),
        input,
      );
      await _apply(tester);
      expect(edited, isNull);
      expect(find.text('1일 횟수를 1~4회로 입력해주세요.'), findsOneWidget);
    });
  }

  for (final count in [1, 2, 3, 4]) {
    // 함수이름: 횟수 변경 후 저장 요청 테스트
    // 함수역할: OCR 행에서 횟수만 고쳐도 실제 저장되는 시간대가 같은 횟수로 바뀌는지 검사한다.
    // 매개변수: tester 화면 시험 도구. 반환값: 비동기 검증 완료.
    testWidgets('OCR 횟수 $count 수정이 저장 시간대까지 반영된다', (tester) async {
      MedicationSchedule? edited;
      await _openEditor(tester, onChanged: (value) => edited = value);
      await tester.enterText(
        find.byKey(const Key('ocr-edit-frequency')),
        '$count회',
      );
      await _apply(tester);
      expect(edited?.slotKeys, medicationScheduleSlotKeysForFrequency(count));
      Map<String, dynamic>? payload;
      final client = MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"success":true,"id":1}', 200);
      });
      addTearDown(client.close);
      final control = CheckSavedMedication(
        patientHash: 'registration-test',
        client: client,
      );
      final result = await control.saveMedicationDetail(
        const MedicationDetail(
          itemName: '등록 시험약',
          efficacy: '',
          usageMethod: '',
          warning: '',
        ),
        medicationSchedule: edited,
      );
      expect(result.isCompleted, isTrue);
      expect(
        payload?['schedule_slot_keys'],
        medicationScheduleSlotKeysForFrequency(count),
      );
      expect(payload?['daily_frequency'], '$count회');
    });
  }

  // 함수이름: 시간대 직접 변경 테스트
  // 함수역할: 취침 전을 추가하거나 다른 시간대를 제거하면 표시 횟수도 실제 선택에 맞춰지는지 확인한다.
  // 매개변수: tester 화면 시험 도구. 반환값: 비동기 검증 완료.
  testWidgets('OCR 시간대 직접 선택이 횟수와 일치한다', (tester) async {
    MedicationSchedule? edited;
    await _openEditor(tester, onChanged: (value) => edited = value);
    final bedtime = find.byKey(const Key('ocr-edit-slot-bedtime'));
    await tester.ensureVisible(bedtime);
    await tester.tap(bedtime);
    await _apply(tester);
    expect(edited?.slotKeys, ['morning', 'evening', 'bedtime']);
    expect(edited?.dailyFrequencyCount, 3);
  });

  // 함수이름: 다른 필드 수정 시 시간대 보존 테스트
  // 함수역할: 용량만 고치는 경우 사용자가 고른 점심·취침 전 시간대를 기본값으로 바꾸지 않는다.
  // 매개변수: tester 화면 시험 도구. 반환값: 비동기 검증 완료.
  testWidgets('OCR 용량 수정은 기존 사용자 시간대를 유지한다', (tester) async {
    MedicationSchedule? edited;
    await _openEditor(
      tester,
      slots: ['lunch', 'bedtime'],
      onChanged: (value) => edited = value,
    );
    await tester.enterText(find.byKey(const Key('ocr-edit-dosage')), '0.5정');
    await _apply(tester);
    expect(edited?.slotKeys, ['lunch', 'bedtime']);
    expect(edited?.dosage, '0.5정');
  });
}

// 함수이름: _openEditor
// 함수역할: 지정 시간대의 OCR 행을 렌더링하고 실제 수정 대화상자를 연다.
// 매개변수: tester 시험 도구, slots 기존 시간대, onChanged 수정 결과 수신자.
// 반환값: 대화상자 준비 완료 Future.
Future<void> _openEditor(
  WidgetTester tester, {
  List<String> slots = const ['morning', 'evening'],
  required ValueChanged<MedicationSchedule> onChanged,
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: PrescriptionAnalysisPreviewUI(
        medicationScheduleList: [
          MedicationSchedule(
            medicationName: '등록 시험약',
            dosage: '1정',
            intakeTime: '2회',
            medicationTime: 7,
            prescriptionDate: DateTime(2026, 9, 24),
            scheduleSlotKeys: slots,
          ),
        ],
        userSetting: const UserSetting(),
        onBackRequested: () {},
        onAnalysisRequested: () {},
        onMedicationScheduleChanged: (_, value) => onChanged(value),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('ocr-table-cell-0-name')));
  await tester.pumpAndSettle();
}

// 함수이름: _apply
// 함수역할: 실제 적용 버튼으로 수정한 일정의 유효성을 검사하고 대화상자를 닫는다.
// 매개변수: tester 시험 도구. 반환값: 적용 완료 Future.
Future<void> _apply(WidgetTester tester) async {
  final button = find.byKey(const Key('ocr-edit-save'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}
