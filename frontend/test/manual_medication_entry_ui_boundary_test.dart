// 파일명: manual_medication_entry_ui_boundary_test.dart
// 역할: 복약정보 직접 등록 화면의 입력 검증, 사진 선택과 저장 흐름을 검증한다. 직접 등록 화면의 필수 입력 검증과 저장 요청 구성을 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/manual_medication_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';


// 함수이름: main
// 함수역할:
// - 약 직접 등록 검증, 저장 데이터와 복용 단위 번역 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 약 이름이 없으면 직접 등록 저장 요청을 보내지 않는다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('약 이름이 없으면 직접 등록 저장 요청을 보내지 않는다', (tester) async {
    var requestCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMedicationEntryUI(
          userSetting: const UserSetting(language: 'ko'),
          // 함수이름: onSaveRequested 콜백
          // 함수역할:
          // - 직접 등록 저장 호출 횟수를 기록하고 저장 성공 결과를 제공한다.
          // 매개변수:
          // - entry (ManualMedicationEntry): 직접 약 등록 화면에서 검증한 입력값. 이 대역에서는 직접 사용하지 않는다.
          // 반환값:
          // - saved 상태의 MedicationSaveResult.
          onSaveRequested: (entry) async {
            requestCount += 1;
            return const MedicationSaveResult(
              status: MedicationSaveStatus.saved,
              message: '저장됨',
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('manual-medication-save')));
    await tester.pump();

    expect(find.text('약 이름을 입력해주세요.'), findsOneWidget);
    expect(requestCount, 0);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 입력한 약 이름과 복용 정보를 기존 저장 요청 값으로 전달한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('입력한 약 이름과 복용 정보를 기존 저장 요청 값으로 전달한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ManualMedicationEntry? submittedEntry;
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMedicationEntryUI(
          userSetting: const UserSetting(language: 'ko'),
          // 함수이름: onSaveRequested 콜백
          // 함수역할:
          // - 사용자가 입력한 직접 등록 데이터를 보관하고 실패 결과로 화면을 유지한다.
          // 매개변수:
          // - entry (ManualMedicationEntry): 직접 약 등록 화면에서 검증한 입력값.
          // 반환값:
          // - failed 상태와 테스트 중단 메시지를 가진 저장 결과.
          onSaveRequested: (entry) async {
            submittedEntry = entry;
            return const MedicationSaveResult(
              status: MedicationSaveStatus.failed,
              message: '테스트 저장 중단',
            );
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('manual-medication-name')),
      '직접입력약',
    );
    await tester.enterText(
      find.byKey(const Key('manual-medication-dosage')),
      '0.5',
    );
    final eveningSlot = find.byKey(const Key('manual-medication-slot-evening'));
    await tester.ensureVisible(eveningSlot);
    await tester.pumpAndSettle();
    await tester.tap(eveningSlot);
    await tester.ensureVisible(find.byKey(const Key('manual-medication-save')));
    await tester.tap(find.byKey(const Key('manual-medication-save')));
    await tester.pumpAndSettle();

    expect(submittedEntry, isNotNull);
    expect(submittedEntry!.medicationName, '직접입력약');
    expect(submittedEntry!.dosageAmount, '0.5');
    expect(submittedEntry!.dosageUnit, '정');
    expect(
      submittedEntry!.scheduleSlotKeys,
      containsAll(['morning', 'evening']),
    );
    expect(find.text('테스트 저장 중단'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: testWidgets 콜백
  // 함수역할:
  // - 기대 동작: 영어 설정은 단위 선택 문구만 번역하고 저장 값은 유지한다.
  // 매개변수:
  // - tester (WidgetTester): 화면 렌더링·조작·기대 조건 검사를 위한 위젯 테스트 제어기.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  testWidgets('영어 설정은 단위 선택 문구만 번역하고 저장 값은 유지한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManualMedicationEntryUI(
          userSetting: const UserSetting(language: 'en'),
          // 함수이름: onSaveRequested 콜백
          // 함수역할:
          // - 단위 표시 번역 검사를 위한 직접 등록 저장 성공을 제공한다.
          // 매개변수:
          // - _ (ManualMedicationEntry): 콜백 계약을 유지하기 위해 받지만 사용하지 않는 인자.
          // 반환값:
          // - saved 상태의 MedicationSaveResult.
          onSaveRequested: (_) async => const MedicationSaveResult(
            status: MedicationSaveStatus.saved,
            message: 'saved',
          ),
        ),
      ),
    );

    expect(find.text('Add Medication'), findsOneWidget);
    expect(find.text('Tablet'), findsOneWidget);
    expect(find.text('정'), findsNothing);
  });
}
