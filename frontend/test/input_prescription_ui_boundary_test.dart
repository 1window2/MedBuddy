// 파일명: input_prescription_ui_boundary_test.dart
// 역할: 처방전, 낱알약과 직접 등록 입력 방식 선택 화면을 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/boundaries/input_prescription_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/pill_identification_ui_boundary.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';
import 'package:medbuddy_frontend/views/home_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('약 정보 입력은 처방전, 낱알약, 직접 등록 작업을 구분한다', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pillTaskRequested = false;
    var manualTaskRequested = false;
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
          onManualMedicationRequested: () {
            manualTaskRequested = true;
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
    expect(find.text('직접 등록'), findsOneWidget);

    await tester.tap(find.text('낱알약 식별'));
    await tester.pumpAndSettle();
    expect(pillTaskRequested, isTrue);

    await tester.tap(find.text('약 정보 촬영하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('직접 등록'));
    await tester.pumpAndSettle();
    expect(manualTaskRequested, isTrue);
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

  testWidgets('환자 보호자 연동 카드는 다른 홈 카드와 같은 높이와 설명을 제공한다', (tester) async {
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
    expect(find.text('환자와 보호자의 복약 일정을 연결'), findsOneWidget);
    expect(tester.getSize(linkCard).height, tester.getSize(savedCard).height);
    expect(find.byIcon(Icons.people_alt_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('근처 운영 약국 카드는 실험실 기능을 켠 경우에만 표시한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget buildHome({VoidCallback? onNearbyPharmacyRequested}) {
      return MaterialApp(
        home: InputPrescriptionUI(
          statusMessage: '',
          userSetting: const UserSetting(language: 'ko'),
          onPrescriptionScanRequested: () {},
          onPrescriptionGalleryRequested: () {},
          onPillIdentificationRequested: () {},
          onTodayScheduleRequested: () {},
          onSavedMedicationRequested: () {},
          onPatientCaregiverLinkRequested: () {},
          onNearbyPharmacyRequested: onNearbyPharmacyRequested,
          onUserSettingRequested: () {},
        ),
      );
    }

    await tester.pumpWidget(buildHome());
    expect(find.byKey(const ValueKey('homeNearbyPharmacyCard')), findsNothing);

    await tester.pumpWidget(buildHome(onNearbyPharmacyRequested: () {}));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('homeNearbyPharmacyCard')),
      findsOneWidget,
    );
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

    expect(find.text('Your healthy medication companion'), findsOneWidget);
    expect(find.text('오늘의 복약 일정'), findsNothing);
    expect(find.text("Today's Medication"), findsOneWidget);
  });
}
