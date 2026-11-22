import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/link_patient_caregiver_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/controls/manage_linked_chat_control.dart';
import 'package:medbuddy_frontend/entities/chat_message_entity.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/theme/medbuddy_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _link = PatientCaregiverLink(
  linkId: 7,
  patientHash: 'patient-a',
  caregiverHash: 'caregiver-a',
  linkStatus: true,
);

class _Poll {
  final String code;
  final result = Completer<PatientLinkCodeStatus>();
  bool aborted = false;

  _Poll(this.code, Future<void>? abort) {
    abort?.then((_) => aborted = true);
  }
}

class _Control extends LinkPatientCaregiver {
  final polls = <_Poll>[];
  List<PatientCaregiverLink> links = [];
  int reloads = 0;
  int issued = 0;
  bool failReload = false;
  Duration ttl = const Duration(minutes: 15);
  late PatientLinkCode code;

  _Control([String owner = 'patient-a'])
    : super(
        userHash: owner,
        client: MockClient((_) async => http.Response('{}', 500)),
      );

  @override
  Future<List<PatientCaregiverLink>> requestLinkScreen() async {
    reloads++;
    if (failReload) throw StateError('Refresh unavailable');
    return links;
  }

  @override
  Future<PatientLinkCode> generatePatientHash() async {
    issued++;
    return code = PatientLinkCode(
      code: issued == 1 ? 'ABCD1234' : 'EFGH5678',
      patientHash: userHash,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  @override
  Future<PatientLinkCodeStatus> requestPatientCodeStatus(
    String code, {
    Future<void>? abortTrigger,
  }) {
    final poll = _Poll(code, abortTrigger);
    polls.add(poll);
    return poll.result.future;
  }

  void reply(PatientLinkCodeState state, {int? index}) {
    if (state == PatientLinkCodeState.linked) links = [_link];
    polls[index ?? polls.length - 1].result.complete(
      PatientLinkCodeStatus(
        patientCode: code,
        state: state,
        link: state == PatientLinkCodeState.linked ? _link : null,
      ),
    );
  }
}

class _Chat extends ManageLinkedChat {
  _Chat()
    : super(
        userHash: 'patient-a',
        client: MockClient((_) async => http.Response('{}', 500)),
      );

  @override
  Future<List<ChatMedicationContext>> requestMedicationContexts({
    required int linkId,
  }) async => [];
}

Widget _app(
  _Control control, {
  GlobalKey<NavigatorState>? navigatorKey,
  VoidCallback? onChanged,
  bool english = true,
  double scale = 1,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  theme: MedBuddyTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: LinkPatientCaregiverUI(
    initialUserHash: control.userHash,
    userSetting: UserSetting(language: english ? 'en' : 'ko'),
    controlFactory: (_) => control,
    chatControlFactory: (_) => _Chat(),
    onLinksChanged: onChanged,
  ),
);

Future<void> _open(WidgetTester tester, {bool english = true}) async {
  await tester.pumpAndSettle();
  final button = find.text(english ? 'Create patient code' : '환자 코드 생성');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final english in [true, false]) {
    for (final existing in [true, false]) {
      testWidgets(
        'exact-code success reuses result dialog en=$english existing=$existing',
        (tester) async {
          tester.view.physicalSize = const Size(320, 520);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final control = _Control()..links = existing ? [_link] : [];
          var changed = 0;
          await tester.pumpWidget(
            _app(
              control,
              english: english,
              scale: 2,
              onChanged: () => changed++,
            ),
          );
          await _open(tester, english: english);
          expect(control.polls, hasLength(1));
          expect(
            find.byKey(const Key('patient-link-result-dialog')),
            findsNothing,
          );
          control.reply(PatientLinkCodeState.pending);
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(control.polls, hasLength(2));
          control.failReload = true;
          control.reply(PatientLinkCodeState.linked);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('patientCodeValue')), findsNothing);
          expect(
            find.text(english ? 'Link complete' : '연동 완료'),
            findsOneWidget,
          );
          final result = find.byKey(const Key('patient-link-result-dialog'));
          expect(result, findsOneWidget);
          final dialog = tester.widget<AlertDialog>(result);
          expect(dialog.backgroundColor, MedBuddyColors.surface);
          expect(dialog.constraints, const BoxConstraints(maxWidth: 328));
          expect(dialog.scrollable, isTrue);
          expect(tester.getCenter(find.byType(Dialog)).dx, closeTo(160, 1));
          expect(changed, 1);
          expect(control.reloads, 2);
          await tester.pump(const Duration(seconds: 20));
          expect(control.polls, hasLength(2));
          final confirm = find.byKey(const Key('patient-link-result-confirm'));
          await tester.ensureVisible(confirm);
          final close = tester.widget<FilledButton>(confirm).onPressed!;
          close();
          close();
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(find.byType(LinkPatientCaregiverUI), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('one in-flight poll and transient errors retry without success', (
    tester,
  ) async {
    final control = _Control();
    await tester.pumpWidget(_app(control));
    await _open(tester);
    await tester.pump(const Duration(seconds: 12));
    expect(control.polls, hasLength(1));
    control.polls.single.result.completeError(TimeoutException('offline'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(control.polls, hasLength(2));
    expect(find.byKey(const Key('patient-link-result-dialog')), findsNothing);
    control.reply(PatientLinkCodeState.linked);
    await tester.pumpAndSettle();
    expect(find.text('Link complete'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final lifecycle in [
    AppLifecycleState.inactive,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.detached,
  ]) {
    testWidgets('pause and resume recheck without overlap: $lifecycle', (
      tester,
    ) async {
      final control = _Control();
      await tester.pumpWidget(_app(control));
      await _open(tester);
      tester.binding.handleAppLifecycleStateChanged(lifecycle);
      await tester.pump(const Duration(seconds: 8));
      expect(control.polls.single.aborted, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(control.polls, hasLength(1));
      control.reply(PatientLinkCodeState.linked);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Link complete'), findsNothing);
      expect(control.polls, hasLength(2));
      control.reply(PatientLinkCodeState.linked);
      await tester.pumpAndSettle();
      expect(find.text('Link complete'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final departure in [
    'close',
    'back-transition',
    'barrier',
    'dispose',
    'owner-dispose',
    'account',
  ]) {
    testWidgets('late code success ignored after $departure', (tester) async {
      final control = _Control();
      final navigator = GlobalKey<NavigatorState>();
      var changed = 0;
      await tester.pumpWidget(
        _app(control, navigatorKey: navigator, onChanged: () => changed++),
      );
      await _open(tester);
      switch (departure) {
        case 'close':
          await tester.tap(find.byIcon(Icons.close).last);
        case 'back-transition':
          navigator.currentState!.pop();
        case 'barrier':
          await tester.tapAt(const Offset(2, 2));
        case 'dispose':
          await tester.pumpWidget(const SizedBox.shrink());
        case 'owner-dispose':
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: const Text('Other page'),
            ),
          );
        case 'account':
          await tester.pumpWidget(
            _app(_Control('patient-b'), navigatorKey: navigator),
          );
      }
      control.reply(PatientLinkCodeState.linked);
      await tester.pumpAndSettle();
      expect(control.polls.single.aborted, isTrue);
      expect(changed, 0);
      expect(find.byType(Dialog), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(control.polls, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('expiry cancels an outstanding poll and never resumes it', (
    tester,
  ) async {
    final control = _Control()..ttl = const Duration(seconds: 5);
    await tester.pumpWidget(_app(control));
    await _open(tester);
    await tester.pump(const Duration(seconds: 6));
    expect(control.polls.single.aborted, isTrue);
    control.reply(PatientLinkCodeState.linked);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 10));
    expect(control.polls, hasLength(1));
    expect(find.byKey(const ValueKey('patientCodeRegenerate')), findsOneWidget);
    expect(find.text('Link complete'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'settled background response is discarded and resume checks immediately',
    (tester) async {
      final control = _Control();
      await tester.pumpWidget(_app(control));
      await _open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      control.reply(PatientLinkCodeState.linked);
      await tester.pump(const Duration(seconds: 10));
      expect(control.polls, hasLength(1));
      expect(find.text('Link complete'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(control.polls, hasLength(2));
      control.reply(PatientLinkCodeState.linked);
      await tester.pumpAndSettle();
      expect(find.text('Link complete'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'poll session remains bounded across a long background interval',
    (tester) async {
      final control = _Control()..ttl = const Duration(days: 1);
      await tester.pumpWidget(_app(control));
      await _open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 16));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      control.reply(PatientLinkCodeState.linked);
      await tester.pumpAndSettle();
      expect(control.polls, hasLength(1));
      expect(find.text('Link complete'), findsNothing);
      expect(
        find.byKey(const ValueKey('patientCodeRegenerate')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('already expired code makes no status request', (tester) async {
    final control = _Control()..ttl = Duration.zero;
    await tester.pumpWidget(_app(control));
    await _open(tester);
    expect(control.polls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final state in [
    PatientLinkCodeState.revoked,
    PatientLinkCodeState.expired,
  ]) {
    testWidgets(
      '$state stops polling and regeneration watches only fresh code',
      (tester) async {
        final control = _Control()..links = [_link];
        await tester.pumpWidget(_app(control));
        await _open(tester);
        control.reply(state);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 8));
        expect(control.polls, hasLength(1));
        expect(find.text('Link complete'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('patientCodeRegenerate')));
        await tester.pumpAndSettle();
        expect(control.issued, 2);
        expect(control.polls.last.code, 'EFGH5678');
        control.reply(PatientLinkCodeState.linked);
        await tester.pumpAndSettle();
        expect(find.text('Link complete'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
