// 파일명: health_recommendation_ui_boundary_test.dart
// 역할: 건강 추천의 빈 상태와 약 등록 지름길·오류 재시도·큰 글씨 배치를 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medbuddy_frontend/boundaries/health_recommendation_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/manual_medication_entry_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/medication_capture_options_ui_boundary.dart';
import 'package:medbuddy_frontend/boundaries/pill_identification_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/check_health_recommendation_control.dart';
import 'package:medbuddy_frontend/controls/input_prescription_control.dart';
import 'package:medbuddy_frontend/entities/health_recommendation_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';
import 'package:medbuddy_frontend/viewmodels/medbuddy_view_model.dart';

// 클래스명: _HealthControl
// 역할: 약 없음·오류·정상 응답을 전환하는 건강 추천 대역.
class _HealthControl extends CheckHealthRecommendation {
  bool empty = true;
  bool fail = false;
  int calls = 0;

  // 함수이름: requestHealthRecommendation
  // 함수역할: 선택한 응답 상태와 요청 횟수를 제공한다. 매개변수: language. 반환값: 추천 또는 오류.
  @override
  Future<HealthRecommendation> requestHealthRecommendation({
    String language = 'ko',
  }) async {
    calls++;
    if (fail) throw StateError('Server unavailable');
    if (empty) throw NoActiveMedicationsError();
    return const HealthRecommendation(
      dietRecommendation: 'Diet advice',
      exerciseRecommendation: 'Exercise advice',
      cautionItems: ['Caution'],
      medicationNames: ['Test medication'],
    );
  }
}

// 클래스명: _GalleryInput
// 역할: 실제 사진 선택 없이 기존 갤러리 흐름 호출을 확인한다.
class _GalleryInput extends InputPrescription {
  int calls = 0;

  // 함수이름: requestPrescriptionImageFromGallery
  // 함수역할: 갤러리 요청을 세고 취소를 반환한다. 매개변수: onImageSelected. 반환값: 취소 결과.
  @override
  Future<List<MedicationSchedule>?> requestPrescriptionImageFromGallery({
    PrescriptionImageSelectedCallback? onImageSelected,
  }) async {
    calls++;
    return null;
  }
}

// 클래스명: _ViewModel
// 역할: 건강 추천 제어기와 언어를 주입해 등록 화면을 검증한다.
class _ViewModel extends MedBuddyViewModel {
  final String language;

  // 함수이름: _ViewModel
  // 함수역할: 화면 테스트에 사용할 의존성을 연결한다. 매개변수: control, language, input. 반환값: 테스트 모델.
  _ViewModel(
    _HealthControl control, {
    this.language = 'ko',
    InputPrescription? input,
  }) : super(checkHealthRecommendation: control, inputPrescription: input);

  // 함수이름: userSetting
  // 함수역할: 저장이나 서버 조회 없이 언어를 고정한다. 매개변수: 없음. 반환값: 사용자 설정.
  @override
  UserSetting get userSetting => UserSetting(language: language);
}

// 함수이름: _pumpScreen
// 함수역할: 실제 추천 화면을 동일 계정 Provider와 선택한 글씨 배율로 표시한다. 매개변수: tester, model, scale. 반환값: 표시 완료.
Future<void> _pumpScreen(
  WidgetTester tester,
  MedBuddyViewModel model, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<MedBuddyViewModel>.value(
      value: model,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const HealthRecommendationUI(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// 함수이름: main
// 함수역할: 등록·오류·작은 화면 사례를 등록한다. 매개변수: 없음. 반환값: 없음.
void main() {
  // 함수이름: setUp 콜백
  // 함수역할: 테스트마다 환경설정 저장소를 비운다. 매개변수: 없음. 반환값: 없음.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 함수이름: 직접 등록과 복귀 테스트
  // 함수역할: 공통 메뉴 취소는 추천을 유지하고 직접 등록 후 돌아오면 추천을 갱신한다. 매개변수: tester. 반환값: 검증 완료.
  testWidgets(
    'empty state opens the shared menu and refreshes after manual entry',
    (tester) async {
      final control = _HealthControl();
      final model = _ViewModel(control);
      addTearDown(model.dispose);
      await _pumpScreen(tester, model);
      expect(find.text('현재 복용 중인 약이 없어요'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('healthRegisterMedication')));
      await tester.pumpAndSettle();
      expect(find.text('처방전 분석'), findsOneWidget);
      expect(find.text('낱알약 식별'), findsOneWidget);
      expect(find.text('직접 등록'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(control.calls, 1);
      expect(find.byType(HealthRecommendationUI), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('healthRegisterMedication')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('직접 등록'));
      await tester.pumpAndSettle();
      expect(find.byType(ManualMedicationEntryUI), findsOneWidget);
      control.empty = false;
      Navigator.of(
        tester.element(find.byType(ManualMedicationEntryUI)),
      ).pop(true);
      await tester.pumpAndSettle();
      expect(control.calls, 2);
      expect(model.hasNoActiveHealthMedications, isFalse);
      expect(find.text('Diet advice'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('healthRegisterMedication')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in PillCaptureMode.values) {
    // 함수이름: 낱알약 등록 지름길 테스트
    // 함수역할: 선택한 촬영 방식과 저장 콜백이 기존 식별 화면에 전달된다. 매개변수: tester. 반환값: 검증 완료.
    testWidgets('registration preserves pill capture mode $mode', (
      tester,
    ) async {
      final model = _ViewModel(_HealthControl());
      addTearDown(model.dispose);
      await _pumpScreen(tester, model);
      await tester.tap(find.byKey(const ValueKey('healthRegisterMedication')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('낱알약 식별'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          mode == PillCaptureMode.singlePhoto ? '여러 알약 한 번에 찾기' : '알약 하나씩 찾기',
        ),
      );
      await tester.pumpAndSettle();
      final page = tester.widget<PillIdentificationUI>(
        find.byType(PillIdentificationUI),
      );
      expect(page.captureMode, mode);
      expect(page.onSaveRequested, isNotNull);
      expect(page.onBatchSaveRequested, isNotNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(HealthRecommendationUI), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // 함수이름: 갤러리 분석 진입 테스트
  // 함수역할: 중간 일정 화면이 있어도 최상위 분석 화면으로 돌아와 갤러리 요청을 수행한다. 매개변수: tester. 반환값: 검증 완료.
  testWidgets('gallery registration reveals the root analysis flow', (
    tester,
  ) async {
    final input = _GalleryInput();
    final model = _ViewModel(_HealthControl(), input: input);
    addTearDown(model.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ChangeNotifierProvider<MedBuddyViewModel>.value(
        value: model,
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Schedule')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const HealthRecommendationUI()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('healthRegisterMedication')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('처방전 분석'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();
    expect(input.calls, 1);
    expect(find.text('Home'), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  // 함수이름: 서버 실패와 재시도 테스트
  // 함수역할: 서버 오류에서는 등록을 권하지 않고 재시도하며, 이후 빈 상태나 정상 결과로 전환한다. 매개변수: tester. 반환값: 검증 완료.
  testWidgets('server failures do not claim medications are missing', (
    tester,
  ) async {
    final control = _HealthControl()..fail = true;
    final model = _ViewModel(control);
    addTearDown(model.dispose);
    await _pumpScreen(tester, model);
    expect(model.hasNoActiveHealthMedications, isFalse);
    expect(
      find.byKey(const ValueKey('healthRegisterMedication')),
      findsNothing,
    );
    expect(find.text('건강 관리 추천을 불러오지 못했습니다.'), findsOneWidget);
    control.fail = false;
    await tester.tap(find.text('다시 불러오기'));
    await tester.pumpAndSettle();
    expect(model.hasNoActiveHealthMedications, isTrue);
    expect(
      find.byKey(const ValueKey('healthRegisterMedication')),
      findsOneWidget,
    );
    control.fail = true;
    await tester.tap(find.text('다시 불러오기'));
    await tester.pumpAndSettle();
    expect(model.hasNoActiveHealthMedications, isFalse);
    expect(
      find.byKey(const ValueKey('healthRegisterMedication')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en']) {
    // 함수이름: 빈 상태 접근성 테스트
    // 함수역할: 작은 화면·두 배 글씨에서도 안내와 등록 버튼에 접근할 수 있다. 매개변수: tester. 반환값: 검증 완료.
    testWidgets('empty registration fits 320px at 2x in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = _ViewModel(_HealthControl(), language: language);
      addTearDown(model.dispose);
      await _pumpScreen(tester, model, scale: 2);
      final register = find.byKey(const ValueKey('healthRegisterMedication'));
      await tester.ensureVisible(register);
      await tester.pumpAndSettle();
      expect(register.hitTestable(), findsOneWidget);
      expect(
        find.text(language == 'en' ? 'Add or Identify Medication' : '약 등록·식별'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
