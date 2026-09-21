// 파일명: home_medication_slot_pager_test.dart
// 역할: 홈 시간대 탐색, 선택한 시간대 기록, 보호자 읽기 전용 상태를 검증한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/entities/medication_alarm_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:medbuddy_frontend/widgets/home_medication_slot_pager.dart';

const _medicines = [
  MedicationSchedule(
    medicationID: 'shared',
    medicationName: '아침 저녁약',
    dosage: '1정',
    scheduleSlotKeys: ['morning', 'evening'],
    slotStatuses: {'morning': true, 'evening': false},
  ),
  MedicationSchedule(
    medicationID: 'bedtime',
    medicationName: '취침약',
    scheduleSlotKeys: ['bedtime'],
    slotStatuses: {'bedtime': false},
  ),
];

// 함수이름: _page
// 함수역할: 현재 선택한 시간대의 요약만 찾아 숨겨진 페이지와 구분한다.
// 매개변수: slot: 시간대 키. 반환값: 해당 요약 위젯의 Finder.
Finder _page(String slot) => find.byKey(ValueKey('home-slot-page-$slot'));
final _pager = find.byKey(const Key('home-medication-slot-pager'));
final _completion = find.byKey(const ValueKey('homeNextSlotCompletionButton'));

// 함수이름: main
// 함수역할: 시간대 전환, 기록·취소 및 읽기 전용 표시의 회귀 검증을 등록한다.
// 매개변수: 없음. 반환값: 없음; 각 검증은 테스트 도구가 실행한다.
void main() {
  // 함수이름: 시간대 탐색 테스트
  // 함수역할: 같은 약의 시간대별 완료 상태가 섞이지 않고 마지막 페이지에서 순환하지 않는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('네 시간대를 넘기며 복용 완료·미복용·일정 없음과 같은 약의 시간대별 상태를 구분한다', (
    tester,
  ) async {
    final recorded = <String>[];
    await _show(
      tester,
      onUpdate: (slot, completed) async {
        recorded.add('$slot:$completed');
        return true;
      },
    );
    expect(_page('morning'), findsOneWidget);
    expect(find.text('아침 저녁약'), findsOneWidget);
    expect(find.text('아침 · 복용 완료'), findsOneWidget);
    expect(tester.widget<FilledButton>(_completion).onPressed, isNotNull);
    expect(find.text('복용 취소'), findsOneWidget);
    final height = tester.getSize(_pager).height;
    expect(height, lessThan(110));
    expect(find.byType(TabBar), findsNothing);

    await tester.drag(_pager, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(_page('lunch'), findsOneWidget);
    expect(find.text('이 시간대에 등록된 약이 없습니다.'), findsOneWidget);
    expect(tester.widget<FilledButton>(_completion).onPressed, isNull);
    expect(tester.getSize(_pager).height, height);

    await tester.drag(_pager, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(_page('evening'), findsOneWidget);
    expect(find.text('아침 저녁약'), findsOneWidget);
    expect(find.text('저녁 · 미복용'), findsOneWidget);
    await tester.tap(_completion);
    await tester.pumpAndSettle();
    expect(recorded, ['evening:true']);

    await tester.drag(_pager, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(_page('bedtime'), findsOneWidget);
    expect(find.text('취침약'), findsOneWidget);
    await tester.drag(_pager, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(_page('bedtime'), findsOneWidget);
    expect(recorded, ['evening:true']);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 중복 저장·갱신 테스트
  // 함수역할: 응답을 지연해 중복 전송을 차단하고 새 조회 뒤에도 다음 미복용 시간대를 유지하는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('저장 중 중복 기록을 막고 다음 시간대 선택을 조회 갱신 뒤에도 유지한다', (tester) async {
    final gate = Completer<void>();
    final recorded = <String>[];
    // 함수이름: save
    // 함수역할: 요청을 기록한 뒤 응답을 보류해 연속 누름 상황을 재현한다.
    // 매개변수: slot/completed: 시간대와 완료 여부. 반환값: gate 해제 후 성공.
    Future<bool> save(String slot, bool completed) async {
      recorded.add('$slot:$completed');
      await gate.future;
      return true;
    }

    await _show(tester, onUpdate: save);
    await tester.drag(_pager, const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.drag(_pager, const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.tap(_completion);
    await tester.pump();
    expect(tester.widget<FilledButton>(_completion).onPressed, isNull);
    await tester.tap(_completion);
    await tester.pump();
    expect(recorded, ['evening:true']);
    gate.complete();
    await tester.pumpAndSettle();
    await _show(tester, isLoading: true, onUpdate: save);
    await _show(
      tester,
      onUpdate: save,
      medicines: [
        _medicines.first.copyWith(
          slotStatuses: {'morning': true, 'evening': true},
        ),
        _medicines.last,
      ],
    );
    expect(_page('bedtime'), findsOneWidget);
    expect(find.text('취침 전 · 미복용'), findsOneWidget);
    expect(tester.widget<FilledButton>(_completion).onPressed, isNotNull);
    expect(recorded, ['evening:true']);
  });

  // 함수이름: 보호자 읽기 전용 테스트
  // 함수역할: 환자 상태 조회와 상세 진입만 허용하고 기록 명령이나 추정 시각을 노출하지 않는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('보호자는 시간대별 상태를 조회할 수 있지만 기록 버튼과 추정 알림 시각은 없다', (tester) async {
    var opened = 0;
    await _show(tester, onDetails: () => opened++);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining('08:00'), findsNothing);
    await tester.drag(_pager, const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.drag(_pager, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(find.text('저녁 · 미복용'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-slot-view-schedule')));
    expect(opened, 1);
    expect(find.byType(FilledButton), findsNothing);
  });

  // 함수이름: 조회 상태 구분 테스트
  // 함수역할: 응답을 받지 못한 상태에서 완료 여부를 단정하거나 기록 버튼을 활성화하지 않는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('조회 중과 오류를 빈 일정이나 복용 완료로 표시하지 않는다', (tester) async {
    // 함수이름: save
    // 함수역할: 조회 상태 검증에서 실제 저장 없이 성공 응답만 제공한다.
    // 매개변수: 시간대와 완료 여부는 사용하지 않음. 반환값: 저장 성공.
    Future<bool> save(String _, bool _) async => true;
    await _show(tester, isLoading: true, onUpdate: save);
    expect(find.textContaining('복약 현황 확인 중'), findsOneWidget);
    expect(find.text('아침 저녁약'), findsNothing);
    expect(tester.widget<FilledButton>(_completion).onPressed, isNull);
    await _show(tester, hasError: true, onUpdate: save);
    expect(find.textContaining('복약 현황 확인 필요'), findsOneWidget);
    expect(find.text('이 시간대에 등록된 약이 없습니다.'), findsNothing);
    expect(tester.widget<FilledButton>(_completion).onPressed, isNull);
  });

  for (final language in ['ko', 'en']) {
    // 함수이름: 요약 접근성 테스트
    // 함수역할: 약 이름은 두 줄로 요약하되 큰 글씨에서도 기록 버튼을 터치할 수 있는지 검증한다.
    // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
    testWidgets('좁은 화면의 큰 글씨에서도 간단한 요약과 버튼이 겹치지 않는다: $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _show(
        tester,
        language: language,
        scale: 2,
        medicines: const [
          MedicationSchedule(
            medicationName:
                'A long medication name to verify complete display on a small screen',
            dosage: '1정',
            scheduleSlotKeys: ['morning', 'bedtime'],
          ),
        ],
        onUpdate: (_, _) async => true,
      );
      await tester.drag(_pager, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(_page('lunch'), findsOneWidget);
      await tester.drag(_pager, const Offset(-180, 0));
      await tester.pumpAndSettle();
      await tester.drag(_pager, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(_page('bedtime'), findsOneWidget);
      final name = tester.widget<Text>(
        find.text(
          'A long medication name to verify complete display on a small screen',
        ),
      );
      expect(name.maxLines, 2);
      expect(name.overflow, TextOverflow.ellipsis);
      await tester.ensureVisible(_completion);
      expect(_completion.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: 공통 미리보기 크기 테스트
  // 함수역할: 본인 기록 동작을 보호자 조회 동작으로 바꿔도 같은 내용의 영역 크기가 유지되는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('환자와 보호자 시간대 영역은 같은 내용에서 같은 크기를 유지한다', (tester) async {
    await _show(tester, onUpdate: (_, _) async => true);
    final size = tester.getSize(find.byType(HomeMedicationSlotPager));
    await _show(tester, onDetails: () {});
    expect(tester.getSize(find.byType(HomeMedicationSlotPager)), size);
  });

  // 함수이름: 홈 버튼 형태 테스트
  // 함수역할: 앱 공통 테마에서 기록 버튼의 세 상태를 일정 보기 버튼의 실제 렌더링 결과와 비교한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('복용 완료·취소·비활성 버튼은 일정 보기와 같은 모서리와 크기를 사용한다', (tester) async {
    final theme = MedBuddyTheme.light();
    await _show(tester, theme: theme, onDetails: () {});
    final details = find.byKey(const Key('home-slot-view-schedule'));
    final detailsShape =
        tester
                .widget<Material>(
                  find.descendant(of: details, matching: find.byType(Material)),
                )
                .shape!
            as RoundedRectangleBorder;
    final detailsSize = tester.getSize(details);
    expect(detailsShape.borderRadius, BorderRadius.circular(10));

    for (final slot in ['morning', 'lunch', 'evening']) {
      await _show(
        tester,
        theme: theme,
        initialSlot: slot,
        onUpdate: (_, _) async => true,
      );
      await tester.pumpAndSettle();
      final shape =
          tester
                  .widget<Material>(
                    find.descendant(
                      of: _completion,
                      matching: find.byType(Material),
                    ),
                  )
                  .shape!
              as RoundedRectangleBorder;
      expect(shape.borderRadius, detailsShape.borderRadius, reason: slot);
      expect(tester.getSize(_completion), detailsSize, reason: slot);
    }
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 다수 약 요약 테스트
  // 함수역할: 약이 늘어도 개별 목록을 펼치지 않고 첫 이름과 추가 개수만 표시하는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('약이 많아도 요약은 이름 하나와 나머지 개수로 제한한다', (tester) async {
    await _show(
      tester,
      medicines: [
        for (var index = 0; index < 20; index++)
          MedicationSchedule(
            medicationName: '약 $index',
            scheduleSlotKeys: const ['morning'],
            slotStatuses: {'morning': index < 5},
          ),
      ],
      onUpdate: (_, _) async => true,
    );
    expect(find.text('아침 · 5/20 복용'), findsOneWidget);
    expect(find.text('약 0 외 19개'), findsOneWidget);
    expect(find.text('약 1'), findsNothing);
    expect(tester.getSize(_pager).height, lessThan(110));
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 간단한 일정 정보 테스트
  // 함수역할: 실제 설정된 분 단위 시각을 표시하고 시간대를 넘겨도 긴 주의 문구가 상주하지 않는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('실제 알림 시각과 약 이름만 요약하고 긴 안내는 표시하지 않는다', (tester) async {
    await _show(
      tester,
      initialSlot: 'evening',
      alarms: const {
        'evening': MedicationAlarm(
          slotKey: 'evening',
          hour: 18,
          minute: 55,
          enabled: true,
        ),
      },
    );
    expect(find.text('저녁 · 미복용'), findsOneWidget);
    expect(find.text('18:55 · 아침 저녁약'), findsOneWidget);
    expect(find.textContaining('임의로 추가 복용하지 말고'), findsNothing);
    await tester.drag(_pager, const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('임의로 추가 복용하지 말고'), findsNothing);
  });
  // 함수이름: 기록 후 전환·취소 테스트
  // 함수역할: 다음 일정으로 이동한 뒤 이전 기록을 취소해도 같은 약의 다른 시간대가 바뀌지 않는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('완료 후 다음 일정으로 이동하고 돌아온 시간대만 취소한다', (tester) async {
    var medicines = const [
      MedicationSchedule(
        medicationID: 'shared',
        medicationName: '아침 점심약',
        scheduleSlotKeys: ['morning', 'lunch'],
      ),
    ];
    final writes = <String>[];
    // 함수이름: save
    // 함수역할: 선택한 시간대의 상태만 바꾸고 완료·취소 요청 순서를 기록한다.
    // 매개변수: slot/completed: 시간대와 완료 여부. 반환값: 저장 성공.
    Future<bool> save(String slot, bool completed) async {
      writes.add('$slot:$completed');
      medicines = medicines
          .map(
            (s) =>
                s.copyWith(slotStatuses: {...s.slotStatuses, slot: completed}),
          )
          .toList();
      return true;
    }

    await _show(tester, medicines: medicines, onUpdate: save);
    await tester.tap(_completion);
    await tester.pumpAndSettle();
    await _show(tester, medicines: medicines, onUpdate: save);
    expect(_page('lunch'), findsOneWidget);
    expect(find.text('복용했어요'), findsOneWidget);
    await tester.drag(_pager, const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(find.text('아침 · 복용 완료'), findsOneWidget);
    expect(find.text('복용 취소'), findsOneWidget);
    await tester.tap(_completion);
    await tester.pumpAndSettle();
    await _show(tester, medicines: medicines, onUpdate: save);
    expect(_page('morning'), findsOneWidget);
    expect(find.text('아침 · 미복용'), findsOneWidget);
    expect(find.text('복용했어요'), findsOneWidget);
    expect(writes, ['morning:true', 'morning:false']);
    expect(medicines.single.isSlotCompleted('lunch'), isFalse);
  });

  // 함수이름: 다음 미복용 시간대 선택 테스트
  // 함수역할: 이후 미복용 일정만 선택하고 마지막 기록 후에는 해당 시간대의 취소 동작을 제공하는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('빈 시간대와 완료된 시간대를 건너뛰고 마지막 완료 후에는 취소를 제공한다', (tester) async {
    var medicines = const [
      MedicationSchedule(
        medicationID: 'shared',
        medicationName: '약',
        scheduleSlotKeys: ['morning', 'evening', 'bedtime'],
        slotStatuses: {'evening': true},
      ),
    ];
    // 함수이름: save
    // 함수역할: 다른 시간대 기록을 유지한 채 선택 시간대의 서버 응답을 재현한다.
    // 매개변수: slot/completed: 시간대와 완료 여부. 반환값: 저장 성공.
    Future<bool> save(String slot, bool completed) async {
      medicines = medicines
          .map(
            (s) =>
                s.copyWith(slotStatuses: {...s.slotStatuses, slot: completed}),
          )
          .toList();
      return true;
    }

    await _show(tester, medicines: medicines, onUpdate: save);
    await tester.tap(_completion);
    await tester.pumpAndSettle();
    await _show(tester, medicines: medicines, onUpdate: save);
    expect(_page('bedtime'), findsOneWidget);
    await tester.tap(_completion);
    await tester.pumpAndSettle();
    await _show(tester, medicines: medicines, onUpdate: save);
    expect(_page('bedtime'), findsOneWidget);
    expect(find.text('취침 전 · 복용 완료'), findsOneWidget);
    expect(find.text('복용 취소'), findsOneWidget);
    expect(medicines.single.isSlotCompleted('evening'), isTrue);
    await tester.tap(_completion);
    await tester.pumpAndSettle();
    await _show(tester, medicines: medicines, onUpdate: save);
    expect(medicines.single.isSlotCompleted('morning'), isTrue);
    expect(medicines.single.isSlotCompleted('evening'), isTrue);
    expect(medicines.single.isSlotCompleted('bedtime'), isFalse);
  });

  for (final slot in ['morning', 'evening']) {
    // 함수이름: 기록 실패 복구 테스트
    // 함수역할: 저장 실패를 완료로 표시하거나 다음 페이지로 이동하지 않고 재시도를 허용하는지 검증한다.
    // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
    testWidgets('저장 실패 시 완료·취소 상태와 시간대를 그대로 유지한다: $slot', (tester) async {
      await _show(tester, initialSlot: slot, onUpdate: (_, _) async => false);
      final label = slot == 'morning' ? '복용 취소' : '복용했어요';
      await tester.tap(_completion);
      await tester.pumpAndSettle();
      expect(_page(slot), findsOneWidget);
      expect(find.text(label), findsOneWidget);
      expect(tester.widget<FilledButton>(_completion).onPressed, isNotNull);
    });
  }

  // 함수이름: 저장 중 사용자 탐색 테스트
  // 함수역할: 지연된 저장 응답이 사용자가 새로 선택한 시간대를 덮어쓰지 않는지 검증한다.
  // 매개변수: tester: 화면 조작·검증 도구. 반환값: 비동기 검증 완료.
  testWidgets('저장 중 사용자가 넘긴 시간대는 완료 응답이 와도 유지한다', (tester) async {
    final gate = Completer<bool>();
    await _show(
      tester,
      initialSlot: 'evening',
      onUpdate: (_, _) => gate.future,
    );
    await tester.tap(_completion);
    await tester.pump();
    await tester.drag(_pager, const Offset(180, 0));
    await tester.pump();
    expect(_page('lunch'), findsOneWidget);
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(_page('lunch'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// 함수이름: _show
// 함수역할: 공통 미리보기를 같은 위치에 갱신해 조회 이후에도 선택 상태가 유지되는지 검사한다.
// 매개변수: tester/theme: 렌더링 환경, medicines/alarms: 일정·시각 대역,
//   onUpdate/onDetails: 기록·조회 대역, isLoading/hasError: 조회 상태,
//   language/scale: 언어·글씨 배율, initialSlot: 초기 시간대.
// 반환값: 화면 구성과 한 프레임 갱신을 완료하는 Future<void>.
Future<void> _show(
  WidgetTester tester, {
  ThemeData? theme,
  List<MedicationSchedule> medicines = _medicines,
  Future<bool> Function(String, bool)? onUpdate,
  VoidCallback? onDetails,
  bool isLoading = false,
  bool hasError = false,
  String language = 'ko',
  double scale = 1,
  String initialSlot = 'morning',
  Map<String, MedicationAlarm>? alarms,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: HomeMedicationSlotPager(
            schedules: medicines,
            isEnglish: language == 'en',
            initialSlotKey: initialSlot,
            isLoading: isLoading,
            hasError: hasError,
            reminderSettings: alarms,
            onStatusUpdateRequested: onUpdate,
            showDetailsButton: onUpdate == null && onDetails != null,
            onDetailsRequested: onDetails,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
