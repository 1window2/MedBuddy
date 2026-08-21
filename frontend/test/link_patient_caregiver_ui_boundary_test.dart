import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/link_patient_caregiver_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLinkPatientCaregiver extends LinkPatientCaregiver {
  final List<Completer<List<PatientCaregiverLink>>> linkRequests = [];
  final List<Completer<PatientLinkCode>> codeRequests = [];
  final List<Completer<PatientCaregiverLink>> registrationRequests = [];
  final List<String> registrationCodes = [];
  int disposeCount = 0;

  _FakeLinkPatientCaregiver(String userHash)
    : super(
        userHash: userHash,
        client: MockClient((http.Request request) async {
          return http.Response('{}', 500);
        }),
      );

  @override
  Future<List<PatientCaregiverLink>> requestLinkScreen() {
    final request = Completer<List<PatientCaregiverLink>>();
    linkRequests.add(request);
    return request.future;
  }

  @override
  Future<PatientLinkCode> generatePatientHash() {
    final request = Completer<PatientLinkCode>();
    codeRequests.add(request);
    return request.future;
  }

  @override
  Future<PatientCaregiverLink> requestPatientCaregiverLink(String patientCode) {
    registrationCodes.add(patientCode);
    final request = Completer<PatientCaregiverLink>();
    registrationRequests.add(request);
    return request.future;
  }

  @override
  void dispose() {
    disposeCount += 1;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('link actions stay disabled while one request is in flight', (
    tester,
  ) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    expect(control.linkRequests, hasLength(1));

    const link = PatientCaregiverLink(
      linkId: 1,
      patientHash: 'patient-a',
      caregiverHash: 'caregiver-a',
      linkStatus: true,
    );
    control.linkRequests.single.complete(const [link]);
    await tester.pump();

    final generateButton = find.byType(OutlinedButton).first;
    expect(tester.widget<OutlinedButton>(generateButton).onPressed, isNotNull);
    await tester.tap(generateButton);
    await tester.pump();

    expect(control.codeRequests, hasLength(1));
    for (final button in tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    )) {
      expect(button.onPressed, isNull);
    }
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.medication_outlined),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.close).first,
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(generateButton, warnIfMissed: false);
    await tester.pump();
    expect(control.codeRequests, hasLength(1));

    control.codeRequests.single.complete(
      PatientLinkCode(
        code: 'TEST1234',
        patientHash: 'caregiver-a',
        expiresAt: DateTime.utc(2100),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TEST1234'), findsOneWidget);
    final warningText = find.text(
      '\uD574\uB2F9 \uCF54\uB4DC\uB97C \uBCF4\uD638\uC790 \uC678\n'
      '\uB2E4\uB978 \uC0AC\uB78C\uACFC \uACF5\uC720\uD558\uC9C0 \uB9C8\uC138\uC694!',
    );
    expect(warningText, findsOneWidget);
    expect(tester.widget<Text>(warningText).maxLines, 2);

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(control.linkRequests, hasLength(2));
    control.linkRequests.last.complete(const [link]);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    expect(control.disposeCount, 1);
  });

  testWidgets('stale identity response cannot replace the current link state', (
    tester,
  ) async {
    _useLinkScreenViewport(tester);
    final oldControl = _FakeLinkPatientCaregiver('caregiver-old');
    final currentControl = _FakeLinkPatientCaregiver('caregiver-current');
    final createdHashes = <String>[];

    LinkPatientCaregiver createControl(String userHash) {
      createdHashes.add(userHash);
      return switch (userHash) {
        'caregiver-old' => oldControl,
        'caregiver-current' => currentControl,
        _ => throw StateError('Unexpected user hash: $userHash'),
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-old',
          controlFactory: createControl,
        ),
      ),
    );
    await tester.pump();
    expect(oldControl.linkRequests, hasLength(1));

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-current',
          controlFactory: createControl,
        ),
      ),
    );
    await tester.pump();

    expect(createdHashes, ['caregiver-old', 'caregiver-current']);
    expect(oldControl.disposeCount, 1);
    expect(currentControl.linkRequests, hasLength(1));

    currentControl.linkRequests.single.complete(const [
      PatientCaregiverLink(
        linkId: 2,
        patientHash: 'patient-current',
        caregiverHash: 'caregiver-current',
        linkStatus: true,
      ),
    ]);
    await tester.pump();
    expect(find.text('patient-current'), findsOneWidget);

    oldControl.linkRequests.single.complete(const [
      PatientCaregiverLink(
        linkId: 1,
        patientHash: 'patient-stale',
        caregiverHash: 'caregiver-old',
        linkStatus: true,
      ),
    ]);
    await tester.pump();

    expect(find.text('patient-current'), findsOneWidget);
    expect(find.text('patient-stale'), findsNothing);
    expect(oldControl.disposeCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(oldControl.disposeCount, 1);
    expect(currentControl.disposeCount, 1);
  });

  testWidgets('환자 표시 이름 편집을 취소해도 화면이 유지된다', (tester) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const [
      PatientCaregiverLink(
        linkId: 1,
        patientHash: 'patient-a',
        caregiverHash: 'caregiver-a',
        linkStatus: true,
      ),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('환자 표시 이름 수정'));
    await tester.pumpAndSettle();
    expect(find.text('환자 표시 이름'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    expect(find.text('환자 표시 이름'), findsNothing);
    expect(find.text('환자 NT-A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('환자 표시 이름 저장 결과는 하단에 잠시 안내한다', (tester) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const [
      PatientCaregiverLink(
        linkId: 1,
        patientHash: 'patient-a',
        caregiverHash: 'caregiver-a',
        linkStatus: true,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('총 1개의 연동이 있습니다.'), findsOneWidget);
    await tester.tap(find.byTooltip('환자 표시 이름 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '어머니');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('총 1개의 연동이 있습니다.'), findsOneWidget);
    expect(find.text('어머니 표시 이름을 저장했습니다.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('어머니 표시 이름을 저장했습니다.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('환자 코드를 검증하고 진행 중인 등록 요청을 중복 전송하지 않는다', (tester) async {
    _useLinkScreenViewport(tester);
    final control = _FakeLinkPatientCaregiver('caregiver-a');

    await tester.pumpWidget(
      MaterialApp(
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const []);
    await tester.pumpAndSettle();

    await tester.tap(find.text('환자 관리 등록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('patient-link-code')), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, '등록하기'));
    await tester.pump();

    expect(find.text('환자 코드는 영문과 숫자 8자리로 입력해 주세요.'), findsOneWidget);
    expect(control.registrationRequests, isEmpty);

    await tester.enterText(
      find.byKey(const Key('patient-link-code')),
      'abcd1234',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('patient-link-code')))
          .controller
          ?.text,
      'ABCD1234',
    );

    await tester.tap(find.widgetWithText(FilledButton, '등록하기'));
    await tester.pump();
    expect(control.registrationCodes, ['ABCD1234']);

    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(control.registrationRequests, hasLength(1));

    const link = PatientCaregiverLink(
      linkId: 3,
      patientHash: 'patient-a',
      caregiverHash: 'caregiver-a',
      linkStatus: true,
    );
    control.registrationRequests.single.complete(link);
    await tester.pump();
    expect(control.linkRequests, hasLength(2));
    control.linkRequests.last.complete(const [link]);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient-link-code')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('환자 등록 창은 작은 화면과 큰 글자에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final control = _FakeLinkPatientCaregiver('caregiver-a');

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: LinkPatientCaregiverUI(
          initialUserHash: 'caregiver-a',
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const []);
    await tester.pumpAndSettle();

    await tester.tap(find.text('환자 관리 등록'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('연동 화면과 환자 코드 창은 작은 화면과 2배 글자에서도 스크롤된다', (tester) async {
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final control = _FakeLinkPatientCaregiver('patient-a');

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: LinkPatientCaregiverUI(
          initialUserHash: 'patient-a',
          controlFactory: (_) => control,
        ),
      ),
    );
    await tester.pump();
    control.linkRequests.single.complete(const []);
    await tester.pumpAndSettle();

    final generateButton = find.text('환자 코드 생성');
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();
    await tester.tap(generateButton);
    await tester.pump();
    control.codeRequests.single.complete(
      PatientLinkCode(
        code: 'TEST1234',
        patientHash: 'patient-a',
        expiresAt: DateTime.utc(2100),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TEST1234'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

void _useLinkScreenViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
