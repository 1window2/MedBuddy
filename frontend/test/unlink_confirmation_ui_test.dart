import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/link_patient_caregiver_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UnlinkHarness {
  final deletes = <http.Request>[];
  final response = Completer<http.Response>();
  bool linked = true;
  int updates = 0;
  final controls = <String, LinkPatientCaregiver>{};
  late final client = MockClient((request) async {
    if (request.method == 'DELETE') {
      deletes.add(request);
      return response.future;
    }
    expect(request.method, 'GET');
    final user = request.url.queryParameters['user_hash'];
    return _json({
      'data':
          request.url.path.endsWith('/medications') ||
              !linked ||
              user == 'caregiver-b'
          ? []
          : [_link],
    });
  });

  Map<String, Object> get _link => {
    'link_id': 1,
    'patient_hash': 'patient-a',
    'caregiver_hash': 'caregiver-a',
    'patient_alias': '어머니',
    'caregiver_alias': '우리 딸',
    'link_status': linked,
  };

  Widget screen({String user = 'caregiver-a', String language = 'ko'}) =>
      MaterialApp(
        theme: MedBuddyTheme.light(),
        home: LinkPatientCaregiverUI(
          initialUserHash: user,
          userSetting: UserSetting(language: language),
          controlFactory: (hash) => controls.putIfAbsent(
            hash,
            () => LinkPatientCaregiver(
              baseUrl: 'http://localhost',
              userHash: hash,
              client: client,
            ),
          ),
          chatControlFactory: (hash) =>
              ManageLinkedChat(userHash: hash, client: client),
          onLinksChanged: () => updates++,
        ),
      );

  void complete() {
    linked = false;
    response.complete(_json({'data': _link}));
  }
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<_UnlinkHarness> _pump(
  WidgetTester tester, {
  String user = 'caregiver-a',
  String language = 'ko',
}) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = _UnlinkHarness();
  addTearDown(harness.client.close);
  await tester.pumpWidget(harness.screen(user: user, language: language));
  await tester.pumpAndSettle();
  return harness;
}

Future<VoidCallback> _open(
  WidgetTester tester, {
  String language = 'ko',
}) async {
  final manage = find.text(language == 'en' ? 'Manage link' : '연동 관리');
  await tester.ensureVisible(manage);
  await tester.tap(manage);
  await tester.pumpAndSettle();
  final remove = find.widgetWithText(
    TextButton,
    language == 'en' ? 'Remove link' : '연동 해제',
  );
  await tester.ensureVisible(remove);
  await tester.pumpAndSettle();
  final callback = tester.widget<TextButton>(remove).onPressed!;
  await tester.tap(remove);
  await tester.pumpAndSettle();
  return callback;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dismissal in ['cancel', 'back', 'barrier', 'enter']) {
    testWidgets('unlink $dismissal sends zero DELETE requests', (tester) async {
      final harness = await _pump(tester);
      await _open(tester);
      expect(harness.deletes, isEmpty);
      final staleConfirm = tester.widget<FilledButton>(
        find.byKey(const Key('unlink-confirm')),
      ).onPressed!;
      expect(find.textContaining('어머니 님과의 복약 일정 공유가 중단됩니다.'), findsOneWidget);
      expect(
        find.textContaining('보호자 알림 설정과 두 사람의 대화 기록이 삭제됩니다.'),
        findsOneWidget,
      );
      expect(find.textContaining('환자의 약과 복약 기록은 삭제되지 않습니다.'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('unlink-cancel')))
            .autofocus,
        isTrue,
      );
      if (dismissal == 'cancel') {
        await tester.tap(find.byKey(const Key('unlink-cancel')));
      } else if (dismissal == 'back') {
        await tester.binding.handlePopRoute();
      } else if (dismissal == 'barrier') {
        await tester.tapAt(const Offset(4, 4));
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }
      staleConfirm();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unlink-confirmation-dialog')), findsNothing);
      expect(harness.deletes, isEmpty);
      expect(harness.updates, 0);
      expect(find.byType(LinkPatientCaregiverUI), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'duplicate dialog and confirm inputs send exactly one pending DELETE',
    (tester) async {
      final harness = await _pump(tester);
      final remove = await _open(tester);
      remove();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('unlink-confirmation-dialog')),
        findsOneWidget,
      );
      final confirm = tester
          .widget<FilledButton>(find.byKey(const Key('unlink-confirm')))
          .onPressed!;
      confirm();
      confirm();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      remove();
      await tester.pump();
      expect(harness.deletes, hasLength(1));
      expect(harness.deletes.single.url.path, '/link/1');
      expect(
        harness.deletes.single.url.queryParameters['user_hash'],
        'caregiver-a',
      );
      expect(find.byType(LinkPatientCaregiverUI), findsOneWidget);
      harness.complete();
      await tester.pumpAndSettle();
      expect(harness.updates, 1);
      expect(find.text('환자-보호자 연동을 해제했습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final returnToOriginal in [false, true]) {
    testWidgets(
      'session change invalidates unlink confirmation, return=$returnToOriginal',
      (tester) async {
        final harness = await _pump(tester);
        await _open(tester);
        await tester.pumpWidget(harness.screen(user: 'caregiver-b'));
        await tester.pumpAndSettle();
        if (returnToOriginal) {
          await tester.pumpWidget(harness.screen());
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('unlink-confirm')));
        await tester.pumpAndSettle();
        expect(harness.deletes, isEmpty);
        expect(harness.updates, 0);
        expect(find.text('환자-보호자 연동을 해제했습니다.'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('old DELETE completion cannot clear state after session change', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _open(tester);
    await tester.tap(find.byKey(const Key('unlink-confirm')));
    await tester.pump();
    expect(harness.deletes, hasLength(1));
    await tester.pumpWidget(harness.screen(user: 'caregiver-b'));
    await tester.pumpAndSettle();
    harness.complete();
    await tester.pumpAndSettle();
    expect(harness.updates, 0);
    expect(find.text('환자-보호자 연동을 해제했습니다.'), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('caregiver_patient_label.caregiver-a.patient-a'),
      '어머니',
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    testWidgets(
      'unlink dialog names caregiver and fits large text in $language',
      (tester) async {
        final harness = await _pump(
          tester,
          user: 'patient-a',
          language: language,
        );
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await _open(tester, language: language);
        expect(
          find.descendant(
            of: find.byKey(const Key('unlink-confirmation-dialog')),
            matching: find.textContaining('우리 딸'),
          ),
          findsOneWidget,
        );
        for (final key in ['unlink-cancel', 'unlink-confirm']) {
          final button = find.byKey(Key(key));
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
        }
        expect(harness.deletes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('unlink-cancel')));
        await tester.pumpAndSettle();
      },
    );
  }
}
