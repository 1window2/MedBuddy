import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/input_prescription_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/pill_identification_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/views/home_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('home camera entry separates prescription and pill tasks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pillTaskRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        home: InputPrescriptionUI(
          statusMessage: '',
          userSetting: const UserSetting(language: 'ko'),
          onPrescriptionScanRequested: () {},
          onPrescriptionGalleryRequested: () {},
          onPillIdentificationRequested: () {
            pillTaskRequested = true;
          },
          onTodayScheduleRequested: () {},
          onSavedMedicationRequested: () {},
          onPatientCaregiverLinkRequested: () {},
          onUserSettingRequested: () {},
        ),
      ),
    );

    await tester.tap(find.text('약 정보 촬영하기'));
    await tester.pumpAndSettle();

    expect(find.text('처방전 분석'), findsOneWidget);
    expect(find.text('낱알약 식별'), findsOneWidget);

    await tester.tap(find.text('낱알약 식별'));
    await tester.pumpAndSettle();
    expect(pillTaskRequested, isTrue);
  });

  testWidgets('home owns navigation into loose-pill identification', (
    tester,
  ) async {
    final viewModel = MedBuddyViewModel();
    addTearDown(viewModel.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: viewModel,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    final inputBoundary = tester.widget<InputPrescriptionUI>(
      find.byType(InputPrescriptionUI),
    );
    inputBoundary.onPillIdentificationRequested?.call();
    await tester.pumpAndSettle();

    expect(find.byType(PillIdentificationUI), findsOneWidget);
  });
}
