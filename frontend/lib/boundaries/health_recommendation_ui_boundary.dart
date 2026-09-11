// 파일명: health_recommendation_ui_boundary.dart
// 역할: 건강 관리 추천 요청과 식사·운동·주의사항 표시를 제공한다.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../entities/health_recommendation_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_view_model.dart';
import '../viewmodels/medbuddy_feature_updates.dart';
import 'guided_prescription_camera_ui_boundary.dart';
import 'manual_medication_entry_ui_boundary.dart';
import 'medication_capture_options_ui_boundary.dart';
import 'pill_identification_ui_boundary.dart';

// 파일명: health_recommendation_ui_boundary.dart
// 역할: 약 조합 기반 건강 관리 추천 화면을 구성한다.

// 클래스명: HealthRecommendationUI
// 역할: 건강 추천의 로딩·오류·완료 결과를 담당한다.
// 주요 책임:
// - 화면 진입 시 건강 관리 추천 API 요청을 시작한다.
// - 추천 생성 중, 성공, 실패 상태를 사용자에게 보여준다.
class HealthRecommendationUI extends StatefulWidget {
  // 함수이름: HealthRecommendationUI
  // 함수역할: 건강 추천의 로딩·오류·완료 결과에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // 반환값: 입력 설정이 반영된 HealthRecommendationUI 인스턴스.
  const HealthRecommendationUI({super.key});

  // 함수이름: createState
  // 함수역할: 건강 추천의 로딩·오류·완료 결과의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _HealthRecommendationUIState 인스턴스.
  @override
  State<HealthRecommendationUI> createState() => _HealthRecommendationUIState();
}

// 클래스명: _HealthRecommendationUIState
// 역할: 건강 추천의 로딩·오류·완료 결과의 화면 상태를 관리한다.
// 주요 책임:
// - 건강 추천 제목·뒤로가기와 요청 상태별 본문을 배치한다.
// - 요청 전·로딩·오류·성공을 구분해 추천 콘텐츠 또는 재시도를 표시한다.
class _HealthRecommendationUIState extends State<HealthRecommendationUI> {
  bool _hasRequestedRecommendation = false;
  bool _openingRegistration = false;

  // 함수이름: initState
  // 함수역할: 첫 프레임 뒤 요청 시작 상태를 표시하고 건강 추천 조회를 실행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    // 함수이름: initState.addPostFrameCallback callback
    // 함수역할: 건강 추천의 로딩·오류·완료 결과에서 캡처된 작업 `context.read<MedBuddyViewModel>().fetchHealthRecommendation(); context.read<MedBuddyViewModel>()`을 실행한다.
    // 매개변수:
    // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // 함수이름: initState.setState callback
      // 함수역할: 건강 추천의 로딩·오류·완료 결과의 입력·요청 상태를 `_hasRequestedRecommendation = true`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _hasRequestedRecommendation = true);
      context.read<MedBuddyViewModel>().fetchHealthRecommendation();
    });
  }

  // 함수이름: _openMedicationRegistration
  // 함수역할: 홈과 같은 등록 메뉴를 열고 기존 저장·분석 흐름으로 연결한다. 입력 화면에서 돌아오면 추천을 갱신한다.
  // 매개변수: 없음. 반환값: 등록 화면 또는 선택 취소 처리 완료.
  Future<void> _openMedicationRegistration() async {
    if (_openingRegistration) return;
    setState(() => _openingRegistration = true);
    final viewModel = context.read<MedBuddyViewModel>();
    try {
      final task = await showMedicationCaptureTaskOptions(
        context: context,
        userSetting: viewModel.userSetting,
      );
      if (!mounted || task == null) return;
      if (task == MedicationCaptureTask.manual) {
        await Navigator.push<bool>(
          context,
          MaterialPageRoute<bool>(
            // 함수이름: 직접 등록 화면 builder
            // 함수역할: 현재 계정의 약 저장 명령을 연결한다. 매개변수: context. 반환값: 직접 등록 화면.
            builder: (context) => ManualMedicationEntryUI(
              userSetting: viewModel.userSetting,
              onSaveRequested: viewModel.saveManualMedication,
            ),
          ),
        );
      } else if (task == MedicationCaptureTask.multiplePills ||
          task == MedicationCaptureTask.individualPills) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            // 함수이름: 알약 식별 화면 builder
            // 함수역할: 선택한 촬영 방식과 기존 저장 명령을 연결한다. 매개변수: context. 반환값: 알약 식별 화면.
            builder: (context) => PillIdentificationUI(
              userSetting: viewModel.userSetting,
              captureMode: task == MedicationCaptureTask.multiplePills
                  ? PillCaptureMode.singlePhoto
                  : PillCaptureMode.individualPhotos,
              onSaveRequested: viewModel.saveIdentifiedPill,
              onBatchSaveRequested: viewModel.saveIdentifiedPills,
            ),
          ),
        );
      } else {
        final source = await showPrescriptionImageSourceOptions(
          context: context,
          userSetting: viewModel.userSetting,
        );
        if (!mounted || source == null) return;
        XFile? image;
        if (source == PrescriptionImageSource.camera) {
          image = await Navigator.push<XFile>(
            context,
            MaterialPageRoute<XFile>(
              // 함수이름: 처방전 촬영 화면 builder
              // 함수역할: 기존 촬영 가이드를 재사용한다. 매개변수: context. 반환값: 처방전 카메라.
              builder: (context) => GuidedPrescriptionCameraUI(
                userSetting: viewModel.userSetting,
              ),
            ),
          );
          if (!mounted || image == null) return;
        }
        // 일정·채팅을 거쳐 진입했어도 최상위 홈이 관리하는 OCR 진행 화면을 가리지 않는다.
        Navigator.of(context).popUntil((route) => route.isFirst);
        if (image != null) {
          await viewModel.requestCapturedPrescriptionImage(image);
        } else {
          await viewModel.requestPrescriptionImageFromGallery();
        }
        return;
      }
      if (mounted) await viewModel.fetchHealthRecommendation();
    } finally {
      if (mounted) setState(() => _openingRegistration = false);
    }
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 건강 추천의 로딩·오류·완료 결과 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 건강 추천의 로딩·오류·완료 결과에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<MedBuddyViewModel>();
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewModel.updatesFor(MedBuddyFeature.healthRecommendation),
        viewModel.updatesFor(MedBuddyFeature.userSetting),
      ]),
      // 함수이름: build.builder callback
      // 함수역할: 건강 추천의 로딩·오류·완료 결과에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context, _) => _buildScreen(context, viewModel),
    );
  }

  // 함수이름: _buildScreen
  // 함수역할: 건강 추천 제목·뒤로가기와 요청 상태별 본문을 배치한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // - viewModel (MedBuddyViewModel): 화면 상태·사용자 설정·복약 작업을 제공하는 ViewModel.
  // 반환값: 건강 추천의 로딩·오류·완료 결과에 쓰는 위젯 트리.
  Widget _buildScreen(BuildContext context, MedBuddyViewModel viewModel) {
    final text = _HealthRecommendationText(viewModel.userSetting.language);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _HealthRecommendationHeader(
            text: text,
            // 함수이름: _buildScreen.onBackRequested callback
            // 함수역할: `Navigator.pop(context)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            onBackRequested: () => Navigator.pop(context),
          ),
          Expanded(child: _buildContent(viewModel, text)),
        ],
      ),
    );
  }

  // 함수이름: _buildContent
  // 함수역할: 요청 전·로딩·오류·성공을 구분해 추천 콘텐츠 또는 재시도를 표시한다.
  // 매개변수:
  // - viewModel (MedBuddyViewModel): 화면 상태·사용자 설정·복약 작업을 제공하는 ViewModel.
  // - text (_HealthRecommendationText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 건강 추천의 로딩·오류·완료 결과에 쓰는 위젯 트리.
  Widget _buildContent(
    MedBuddyViewModel viewModel,
    _HealthRecommendationText text,
  ) {
    if (!_hasRequestedRecommendation ||
        viewModel.isHealthRecommendationLoading) {
      return _HealthRecommendationLoading(text: text);
    }

    final recommendation = viewModel.healthRecommendation;
    if (recommendation == null) {
      return _HealthRecommendationError(
        text: text,
        message: viewModel.hasNoActiveHealthMedications
            ? text.emptyMessage
            : viewModel.statusMessage,
        isEmpty: viewModel.hasNoActiveHealthMedications,
        onRegisterRequested: _openingRegistration
            ? null
            : _openMedicationRegistration,
        onRetryRequested: viewModel.fetchHealthRecommendation,
      );
    }

    return _HealthRecommendationContent(
      recommendation: recommendation,
      text: text,
    );
  }
}

// 클래스명: _HealthRecommendationLoading
// 역할: 건강 추천 생성 중 진행 표시를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 건강 추천 생성 중 진행 표시 위젯을 구성한다.
class _HealthRecommendationLoading extends StatelessWidget {
  final _HealthRecommendationText text;

  // 함수이름: _HealthRecommendationLoading
  // 함수역할: 건강 추천 생성 중 진행 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_HealthRecommendationText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _HealthRecommendationLoading 인스턴스.
  const _HealthRecommendationLoading({required this.text});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 건강 추천 생성 중 진행 표시 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 건강 추천 생성 중 진행 표시에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 326),
          padding: const EdgeInsets.fromLTRB(28, 38, 28, 34),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: MedBuddyRadii.largeCard,
            boxShadow: MedBuddyShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text.loadingTitle,
                style: const TextStyle(
                  color: MedBuddyColors.textStrong,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 34),
              const SizedBox(
                width: 92,
                height: 92,
                child: CircularProgressIndicator(
                  color: MedBuddyColors.primary,
                  backgroundColor: MedBuddyColors.mint,
                  strokeWidth: 10,
                ),
              ),
              const SizedBox(height: 34),
              Text(
                text.loadingMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MedBuddyColors.primary,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                text.loadingWait,
                style: const TextStyle(
                  color: MedBuddyColors.textMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 클래스명: _HealthRecommendationHeader
// 역할: 건강 추천 제목과 돌아가기를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 건강 추천 제목과 돌아가기 위젯을 구성한다.
// 속성:
// - onBackRequested (VoidCallback): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
class _HealthRecommendationHeader extends StatelessWidget {
  final _HealthRecommendationText text;
  final VoidCallback onBackRequested;

  // 함수이름: _HealthRecommendationHeader
  // 함수역할: 건강 추천 제목과 돌아가기에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_HealthRecommendationText): 해당 화면 구역의 언어별 표시 문구.
  // - onBackRequested (VoidCallback): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _HealthRecommendationHeader 인스턴스.
  const _HealthRecommendationHeader({
    required this.text,
    required this.onBackRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 건강 추천 제목과 돌아가기 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 건강 추천 제목과 돌아가기에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: MedBuddyColors.topBar,
      padding: EdgeInsets.fromLTRB(
        18,
        MediaQuery.of(context).padding.top + 12,
        24,
        22,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: text.back,
            onPressed: onBackRequested,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 31),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 클래스명: _HealthRecommendationContent
// 역할: 식사·운동 추천과 주의사항 본문을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 식사·운동 추천과 주의사항 본문 위젯을 구성한다.
// 속성:
// - recommendation (HealthRecommendation): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
class _HealthRecommendationContent extends StatelessWidget {
  final HealthRecommendation recommendation;
  final _HealthRecommendationText text;

  // 함수이름: _HealthRecommendationContent
  // 함수역할: 식사·운동 추천과 주의사항 본문에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - recommendation (HealthRecommendation): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
  // - text (_HealthRecommendationText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _HealthRecommendationContent 인스턴스.
  const _HealthRecommendationContent({
    required this.recommendation,
    required this.text,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 식사·운동 추천과 주의사항 본문 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 식사·운동 추천과 주의사항 본문에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final bottomSafeArea = MediaQuery.viewPaddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(42, 24, 42, bottomSafeArea + 28),
      children: [
        _RecommendationCard(
          title: text.diet,
          body: recommendation.dietRecommendation,
          icon: Icons.local_dining_outlined,
          iconColor: const Color(0xFFEC003F),
          headerColor: const Color(0xFFFFF1F2),
        ),
        const SizedBox(height: 16),
        _RecommendationCard(
          title: text.exercise,
          body: recommendation.exerciseRecommendation,
          icon: Icons.directions_walk_rounded,
          iconColor: const Color(0xFF155DFC),
          headerColor: const Color(0xFFEFF6FF),
        ),
        const SizedBox(height: 16),
        _CautionCard(
          title: text.caution,
          cautionItems: recommendation.cautionItems,
        ),
      ],
    );
  }
}

// 클래스명: _RecommendationCard
// 역할: 식사 또는 운동 추천의 제목과 설명을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 식사 또는 운동 추천의 제목과 설명 위젯을 구성한다.
// 속성:
// - title (String): 화면·구역·항목에 표시할 제목.
// - body (String): 앞뒤 공백 제거 후 전송할 메시지 본문.
// - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
// - iconColor (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
class _RecommendationCard extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;
  final Color iconColor;
  final Color headerColor;

  // 함수이름: _RecommendationCard
  // 함수역할: 식사 또는 운동 추천의 제목과 설명에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - body (String): 앞뒤 공백 제거 후 전송할 메시지 본문.
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // - iconColor (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
  // - headerColor (Color): 문자·아이콘·상태 가이드에 적용할 전경 또는 강조 색상.
  // 반환값: 입력 설정이 반영된 _RecommendationCard 인스턴스.
  const _RecommendationCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.iconColor,
    required this.headerColor,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 식사 또는 운동 추천의 제목과 설명 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 식사 또는 운동 추천의 제목과 설명에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: const Color.fromRGBO(0, 0, 0, 0.12),
      borderRadius: MedBuddyRadii.card,
      child: ClipRRect(
        borderRadius: MedBuddyRadii.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              color: headerColor,
              padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
              child: Row(
                children: [
                  Icon(icon, color: iconColor, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: Text(
                body,
                style: const TextStyle(
                  color: MedBuddyColors.textBody,
                  fontSize: 17,
                  height: 1.62,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 클래스명: _CautionCard
// 역할: 건강 추천에 수반되는 주의사항 목록을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 건강 추천에 수반되는 주의사항 목록 위젯을 구성한다.
// 속성:
// - title (String): 화면·구역·항목에 표시할 제목.
// - cautionItems (List<String>): 표시·정리할 설명 또는 주의 문구 목록.
class _CautionCard extends StatelessWidget {
  final String title;
  final List<String> cautionItems;

  // 함수이름: _CautionCard
  // 함수역할: 건강 추천에 수반되는 주의사항 목록에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - cautionItems (List<String>): 표시·정리할 설명 또는 주의 문구 목록.
  // 반환값: 입력 설정이 반영된 _CautionCard 인스턴스.
  const _CautionCard({required this.title, required this.cautionItems});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 건강 추천에 수반되는 주의사항 목록 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 건강 추천에 수반되는 주의사항 목록에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('healthRecommendationCautionCard'),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: const Color(0xFFFEE685), width: 1.5),
        boxShadow: MedBuddyShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFFEE685))),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFE17100),
                  size: 27,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in cautionItems) ...[
                  _CautionItem(text: item),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Class Name: _CautionItem
// Role: Represents one emphasized health-recommendation caution.
// Responsibilities:
// - Composes one emphasized health-recommendation caution using the display values and actions supplied by its parent.
class _CautionItem extends StatelessWidget {
  final String text;

  // 함수이름: _CautionItem
  // 함수역할: 주의사항 한 항목의 강조 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (String): 해당 라벨 또는 정보 행에 표시할 문자열.
  // 반환값: 입력 설정이 반영된 _CautionItem 인스턴스.
  const _CautionItem({required this.text});

  // Function Name: build
  // Description: Renders one emphasized health-recommendation caution from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for one emphasized health-recommendation caution.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
            color: MedBuddyColors.slotMorning,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// 클래스명: _HealthRecommendationError
// 역할: 건강 추천 실패 안내와 재시도를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 건강 추천 실패 안내와 재시도 위젯을 구성한다.
// 속성:
// - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
// - onRetryRequested (Future<void> Function()): 실패하거나 오래된 화면 데이터를 다시 조회할 콜백.
class _HealthRecommendationError extends StatelessWidget {
  final _HealthRecommendationText text;
  final String message;
  final Future<void> Function() onRetryRequested;
  final bool isEmpty;
  final VoidCallback? onRegisterRequested;

  // 함수이름: _HealthRecommendationError
  // 함수역할: 건강 추천 실패 안내와 재시도에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_HealthRecommendationText): 해당 화면 구역의 언어별 표시 문구.
  // - message (String): 현재 작업 결과·오류·상태에 대한 표시 문구.
  // - onRetryRequested (Future<void> Function()): 실패하거나 오래된 화면 데이터를 다시 조회할 콜백.
  // - isEmpty, onRegisterRequested: 복용 약 없음 여부와 등록 메뉴 열기 콜백.
  // 반환값: 입력 설정이 반영된 _HealthRecommendationError 인스턴스.
  const _HealthRecommendationError({
    required this.text,
    required this.message,
    required this.onRetryRequested,
    required this.isEmpty,
    required this.onRegisterRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 건강 추천 실패 안내와 재시도 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 건강 추천 실패 안내와 재시도에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 24),
        child: Center(
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: MedBuddyRadii.largeCard,
              boxShadow: MedBuddyShadows.card,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.health_and_safety_outlined,
                  color: MedBuddyColors.primary,
                  size: 52,
                ),
                const SizedBox(height: 14),
                if (isEmpty) ...[
                  Text(
                    text.emptyTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 17,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                if (isEmpty) ...[
                  FilledButton.icon(
                    key: const ValueKey('healthRegisterMedication'),
                    onPressed: onRegisterRequested,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: Text(
                      text.registerMedication,
                      textAlign: TextAlign.center,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: MedBuddyColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                        letterSpacing: 0,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onRegisterRequested == null
                        ? null
                        : onRetryRequested,
                    icon: const Icon(Icons.refresh),
                    label: Text(text.retry, textAlign: TextAlign.center),
                    style: TextButton.styleFrom(
                      foregroundColor: MedBuddyColors.primaryDark,
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ] else
                  ElevatedButton(
                    onPressed: onRetryRequested,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MedBuddyColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      text.retry,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _HealthRecommendationText
// 역할: 건강 관리 추천 요청과 식사·운동·주의사항 표시에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 건강 관리 추천 요청과 식사·운동·주의사항 표시에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _HealthRecommendationText {
  final String language;

  // 함수이름: _HealthRecommendationText
  // 함수역할: 건강 관리 추천 요청과 식사·운동·주의사항 표시에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _HealthRecommendationText 인스턴스.
  const _HealthRecommendationText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드의 공백과 대소문자를 정리한 뒤 en 접두어로 영어 여부를 판별한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language.trim().toLowerCase().startsWith('en');

  // 함수이름: title
  // 함수역할: 현재 언어와 입력값에 맞춰 "건강 관리 추천" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get title => isEnglish ? 'Health Recommendations' : '건강 관리 추천';
  // 함수이름: back
  // 함수역할: 현재 언어와 입력값에 맞춰 "뒤로가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get back => isEnglish ? 'Back' : '뒤로가기';
  // 함수이름: loadingTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "추천 생성중" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get loadingTitle => isEnglish ? 'Generating' : '추천 생성중';
  // 함수이름: loadingMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "추천 건강 활동을 생성 중입니다" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get loadingMessage =>
      isEnglish ? 'Generating health recommendations' : '추천 건강 활동을 생성 중입니다';
  // 함수이름: loadingWait
  // 함수역할: 현재 언어와 입력값에 맞춰 "잠시만 기다려주세요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get loadingWait => isEnglish ? 'Please wait a moment' : '잠시만 기다려주세요';
  // 함수이름: diet
  // 함수역할: 현재 언어와 입력값에 맞춰 "식사 추천" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get diet => isEnglish ? 'Diet Recommendation' : '식사 추천';
  // 함수이름: exercise
  // 함수역할: 현재 언어와 입력값에 맞춰 "운동 추천" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get exercise => isEnglish ? 'Exercise Recommendation' : '운동 추천';
  // 함수이름: caution
  // 함수역할: 현재 언어와 입력값에 맞춰 "주의사항" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get caution => isEnglish ? 'Cautions' : '주의사항';
  // 함수이름: retry
  // 함수역할: 현재 언어와 입력값에 맞춰 "다시 불러오기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get retry => isEnglish ? 'Try Again' : '다시 불러오기';

  // 함수이름: emptyTitle
  // 함수역할: 추천 대상 약 없음 제목을 제공한다. 매개변수: 없음. 반환값: 언어별 제목.
  String get emptyTitle =>
      isEnglish ? 'No active medications yet' : '현재 복용 중인 약이 없어요';

  // 함수이름: emptyMessage
  // 함수역할: 약 등록 후 이용 가능한 추천을 안내한다. 매개변수: 없음. 반환값: 언어별 안내.
  String get emptyMessage => isEnglish
      ? 'Add your medications to get health recommendations based on what you take.'
      : '약을 등록하면 복용 중인 약에 맞는 건강 관리 추천을 받을 수 있어요.';

  // 함수이름: registerMedication
  // 함수역할: 홈과 같은 약 등록·식별 명령을 표시한다. 매개변수: 없음. 반환값: 언어별 버튼 이름.
  String get registerMedication =>
      isEnglish ? 'Add or Identify Medication' : '약 등록·식별';
}
