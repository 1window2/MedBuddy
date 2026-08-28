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

  testWidgets('환자 보호자 연동 카드는 다른 홈 카드와 같은 높이와 아이콘을 제공한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: InputPrescriptionUI(
          statusMessage: '',
          userSetting: const UserSetting(language: 'ko'),
          onPrescriptionScanRequested: () {},
          onPrescriptionGalleryRequested: () {},
          onPillIdentificationRequested: () {},
          onTodayScheduleRequested: () {},
          onSavedMedicationRequested: () {},
          onPatientCaregiverLinkRequested: () {},
          onUserSettingRequested: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final savedCard = find.byKey(const ValueKey('homeSavedMedicationCard'));
    final linkCard = find.byKey(const ValueKey('homePatientCaregiverLinkCard'));
    expect(tester.getSize(linkCard).height, tester.getSize(savedCard).height);
    expect(find.byIcon(Icons.people_alt_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('영어 설정은 메인 화면 제목과 설명에 함께 반영된다', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: InputPrescriptionUI(
          statusMessage: '',
          userSetting: const UserSetting(language: 'en'),
          onPrescriptionScanRequested: () {},
          onPrescriptionGalleryRequested: () {},
          onPillIdentificationRequested: () {},
          onTodayScheduleRequested: () {},
          onSavedMedicationRequested: () {},
          onPatientCaregiverLinkRequested: () {},
          onUserSettingRequested: () {},
        ),
      ),
    );

    expect(find.text('Start your medication plan with ease'), findsOneWidget);
    expect(find.text('오늘의 복약 일정'), findsNothing);
    expect(find.text("Today's Medication"), findsOneWidget);
  });
}
