import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/link_patient_caregiver_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/link_patient_caregiver_control.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';

class _FakeLinkPatientCaregiver extends LinkPatientCaregiver {
  final List<Completer<List<PatientCaregiverLink>>> linkRequests = [];
  final List<Completer<PatientLinkCode>> codeRequests = [];
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
  void dispose() {
    disposeCount += 1;
  }
}

void main() {
  testWidgets('link actions stay disabled while one request is in flight',
      (tester) async {
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
    for (final button
        in tester.widgetList<OutlinedButton>(find.byType(OutlinedButton))) {
      expect(button.onPressed, isNull);
    }
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
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

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(control.linkRequests, hasLength(2));
    control.linkRequests.last.complete(const [link]);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    expect(control.disposeCount, 1);
  });

  testWidgets('stale identity response cannot replace the current link state',
      (tester) async {
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

    currentControl.linkRequests.single.complete(
      const [
        PatientCaregiverLink(
          linkId: 2,
          patientHash: 'patient-current',
          caregiverHash: 'caregiver-current',
          linkStatus: true,
        ),
      ],
    );
    await tester.pump();
    expect(find.text('patient-current'), findsOneWidget);

    oldControl.linkRequests.single.complete(
      const [
        PatientCaregiverLink(
          linkId: 1,
          patientHash: 'patient-stale',
          caregiverHash: 'caregiver-old',
          linkStatus: true,
        ),
      ],
    );
    await tester.pump();

    expect(find.text('patient-current'), findsOneWidget);
    expect(find.text('patient-stale'), findsNothing);
    expect(oldControl.disposeCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(oldControl.disposeCount, 1);
    expect(currentControl.disposeCount, 1);
  });
}

void _useLinkScreenViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
