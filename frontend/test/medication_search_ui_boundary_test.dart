import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/medication_search_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/check_medication_detail_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manual_medication_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_medication_detail_control.dart';
import 'package:medbuddy_frontend/controls/check_saved_medication_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_match_review_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/manual_medication_entry_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

const _drug = MedicationDetail(
  itemSeq: '123',
  itemName: '시험약 10mg',
  manufacturer: '시험 제약',
  efficacy: '',
  usageMethod: '',
  warning: '',
);

class _Lookup extends CheckMedicationDetail {
  _Lookup(this.request)
    : super(client: MockClient((_) async => http.Response('{}', 500)));
  final Future<MedicationDetail?> Function() request;
  int calls = 0;
  @override
  Future<MedicationDetail?> requestMedicationDetail(
    MedicationSchedule schedule,
  ) {
    calls++;
    return request();
  }
}

Future<void> _search(
  WidgetTester tester,
  _Lookup lookup, {
  bool selection = false,
  bool english = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MedicationSearchUI(
        userSetting: UserSetting(language: english ? 'en' : 'ko'),
        lookupControl: lookup,
        selectionMode: selection,
      ),
    ),
  );
  await tester.enterText(
    find.byKey(const Key('medication-search-query')),
    '시험약',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('medication-search-submit')));
  await tester.pump();
}

void main() {
  testWidgets('후보는 사용자가 확인한 뒤 선택하며 취소하면 검색에 남는다', (tester) async {
    final lookup = _Lookup(
      () async => throw MedicationMatchReview([_drug, _drug]),
    );
    await _search(tester, lookup, selection: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medication-search-result-0')), findsOneWidget);
    expect(find.byKey(const Key('medication-search-result-1')), findsNothing);
    await tester.tap(find.byKey(const Key('medication-search-result-0')));
    await tester.pumpAndSettle();
    expect(find.text('약품 정보 확인'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(MedicationSearchUI), findsOneWidget);
    expect(lookup.calls, 1);
  });

  testWidgets('입력 변경 후 도착한 이전 결과를 표시하지 않는다', (tester) async {
    final gate = Completer<MedicationDetail?>();
    final lookup = _Lookup(() => gate.future);
    await _search(tester, lookup);
    await tester.enterText(
      find.byKey(const Key('medication-search-query')),
      '다른약',
    );
    gate.complete(_drug);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medication-search-result-0')), findsNothing);
    expect(lookup.calls, 1);
  });

  testWidgets('검색 실패는 빈 결과와 구별되며 다시 검색할 수 있다', (tester) async {
    var fail = true;
    final lookup = _Lookup(() async {
      if (fail) throw StateError('private server details');
      return null;
    });
    await _search(tester, lookup, english: true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not search'), findsOneWidget);
    expect(find.textContaining('private server details'), findsNothing);
    fail = false;
    await tester.tap(find.byKey(const Key('medication-search-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No medications found'), findsOneWidget);
  });

  testWidgets('독립 검색은 등록하지 않고 기존 상세 화면을 연다', (tester) async {
    await _search(tester, _Lookup(() async => _drug));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medication-search-result-0')));
    await tester.pumpAndSettle();
    expect(find.byType(CheckMedicationDetailUI), findsOneWidget);
  });

  testWidgets('좁은 화면 큰 글자에서도 긴 약 이름과 제조사가 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: MedicationSearchUI(
          userSetting: const UserSetting(),
          initialQuery: '시험약',
          lookupControl: _Lookup(
            () async =>
                _drug.copyWith(itemName: '아주 긴 시험용 약 이름(함량과 제형이 포함된 제품명)'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('medication-search-submit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final editName in [false, true]) {
    testWidgets('직접 등록에서 검색 약 정보를 유지하고 이름 변경 시 해제 ($editName)', (tester) async {
      tester.view.physicalSize = const Size(440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ManualMedicationEntry? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: ManualMedicationEntryUI(
            userSetting: const UserSetting(),
            onSaveRequested: (entry) async {
              saved = entry;
              return const MedicationSaveResult(
                status: MedicationSaveStatus.failed,
                message: 'test',
              );
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('manual-medication-search')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(MedicationSearchUI))).pop(_drug);
      await tester.pumpAndSettle();
      expect(find.text(_drug.itemName), findsOneWidget);
      if (editName) {
        await tester.enterText(
          find.byKey(const Key('manual-medication-name')),
          '다른약',
        );
      }
      await tester.tap(find.byKey(const Key('manual-medication-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.catalogMedication, editName ? isNull : same(_drug));
      expect(saved!.dosageAmount, '1');
      expect(saved!.scheduleSlotKeys, ['morning']);
    });
  }
}
