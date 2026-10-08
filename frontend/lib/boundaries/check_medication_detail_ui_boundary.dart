// File Name: check_medication_detail_ui_boundary.dart
// Role: UI boundaries and helpers for medication indications, dosage, precautions, and spoken guidance.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../controls/request_voice_guide_control.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_image_url_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/medbuddy_page_header.dart';
import 'medication_image_viewer_boundary.dart';

// 파일명: check_medication_detail_ui_boundary.dart
// 역할: 약 상세정보 화면을 구성하고 음성 안내 요청을 처리한다.

// Class Name: CheckMedicationDetailUI
// Role: Represents medication details with indications, dosage, precautions, and read-aloud controls.
// Responsibilities:
// - Provides reusable details for the saved list and today's schedule.
// - Reads indications, dosage, precautions, and detailed guidance using the configured speech rate and language.
// - Stops reading aloud when the screen closes or the app moves to the background.
// Attributes:
// - medicationDetail (MedicationDetail): Medication data to display, transform, save, or compare.
// - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
// - requestVoiceGuide (RequestVoiceGuide?): Voice-guide control to use instead of creating one; the caller keeps ownership and disposes it.
class CheckMedicationDetailUI extends StatefulWidget {
  final MedicationDetail medicationDetail;
  final UserSetting userSetting;
  final RequestVoiceGuide? requestVoiceGuide;

  // Function Name: CheckMedicationDetailUI
  // Description: Initializes medication details with indications, dosage, precautions, and read-aloud controls with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - medicationDetail (MedicationDetail): Medication data to display, transform, save, or compare.
  // - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
  // - requestVoiceGuide (RequestVoiceGuide?): Optional voice-guide control owned by the caller; when omitted the screen creates and disposes its own.
  // Returns: Initialized CheckMedicationDetailUI instance.
  const CheckMedicationDetailUI({
    super.key,
    required this.medicationDetail,
    required this.userSetting,
    this.requestVoiceGuide,
  });

  // Function Name: createState
  // Description: Creates the state object that coordinates medication details with indications, dosage, precautions, and read-aloud controls.
  // Parameters:
  // - None.
  // Returns: A new _CheckMedicationDetailUIState instance.
  @override
  State<CheckMedicationDetailUI> createState() =>
      _CheckMedicationDetailUIState();
}

// 클래스명: _CheckMedicationDetailUIState
// 역할: 효능·복용법·주의사항과 읽어주기 기능을 갖춘 약 상세의 화면 상태를 관리한다.
// 주요 책임:
// - 읽어주기를 시작하거나 중지하고 완료·오류 시 재생 상태를 해제한다.
// - 앱이 백그라운드로 가면 읽어주기를 중지한다.
// 속성:
// - _isSpeaking (bool): 읽어주기가 현재 재생 중인지 여부.
class _CheckMedicationDetailUIState extends State<CheckMedicationDetailUI>
    with WidgetsBindingObserver {
  late final RequestVoiceGuide _requestVoiceGuide;
  // 화면이 직접 만든 음성 안내 Control만 화면 종료 때 정리한다.
  late final bool _ownsRequestVoiceGuide;
  bool _isSpeaking = false;

  // Function Name: initState
  // Description: Selects the injected or a newly created voice-guide control and starts observing app lifecycle changes.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void initState() {
    super.initState();
    final injectedRequestVoiceGuide = widget.requestVoiceGuide;
    _requestVoiceGuide = injectedRequestVoiceGuide ?? RequestVoiceGuide();
    _ownsRequestVoiceGuide = injectedRequestVoiceGuide == null;
    WidgetsBinding.instance.addObserver(this);
  }

  // Function Name: didChangeAppLifecycleState
  // Description: Stops reading aloud when the app moves to the background so speech does not continue over another app.
  // Parameters:
  // - state (AppLifecycleState): New lifecycle state of the app.
  // Returns: None; updates state or performs the documented action.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isSpeaking) {
      unawaited(_stopVoiceGuide());
    }
  }

  // Function Name: dispose
  // Description: Stops observing the app lifecycle, stops playback, releases a voice-guide control this screen created, and detaches this screen from active updates.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requestVoiceGuide.stop();
    if (_ownsRequestVoiceGuide) {
      _requestVoiceGuide.dispose();
    }
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 공통 헤더 아래 복용 요약을 한 번 표시하고 상세 복용법·위험 정보와 읽어주기를 유지한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 효능·복용법·주의사항과 읽어주기 기능을 갖춘 약 상세에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final text = _MedicationDetailText(widget.userSetting.language);

    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            MedBuddyPageHeader(
              title: text.title,
              subtitle: text.isEnglish
                  ? 'Check uses, dosage and precautions.'
                  : '효능과 복용법, 주의사항을 확인합니다.',
              backTooltip: text.back,
              // 함수이름: onBackRequested 콜백
              // 함수역할: 이전 화면으로 돌아간다. 매개변수: 없음. 반환값: 없음.
              onBackRequested: () => Navigator.pop(context),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: MedBuddySpacing.contentMaxWidth,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: [
                      _MedicationHeroCard(
                        medicationDetail: widget.medicationDetail,
                        displayName: widget.medicationDetail
                            .displayNameForLanguage(
                              widget.userSetting.language,
                            ),
                        language: widget.userSetting.language,
                      ),
                      const SizedBox(height: 24),
                      _DetailQuestionSection(
                        title: text.efficacyQuestion,
                        values: _summaryValues(
                          widget.medicationDetail.efficacy,
                          text.noInformation,
                        ),
                        noInformation: text.noInformation,
                      ),
                      const SizedBox(height: 24),
                      _DetailQuestionSection(
                        title: text.dosageQuestion,
                        subtitle: text.registeredDosage,
                        values: widget.medicationDetail
                            .compactDosageGuideLinesForLanguage(
                              widget.userSetting.language,
                            ),
                        noInformation: text.noInformation,
                      ),
                      const SizedBox(height: 22),
                      _DetailedDosageGuideCard(
                        medicationDetail: widget.medicationDetail,
                        text: text,
                      ),
                      const SizedBox(height: 18),
                      _MedicationRiskCard(
                        medicationDetail: widget.medicationDetail,
                        text: text,
                      ),
                      const SizedBox(height: 18),
                      _MedicationChecklistCard(
                        medicationDetail: widget.medicationDetail,
                        text: text,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 읽어주기는 별도 영역에 고정해 상세 본문을 가리지 않는다.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: MedBuddySpacing.contentMaxWidth,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: _TtsButton(
                      isSpeaking: _isSpeaking,
                      onPressed: _handleTtsButtonPressed,
                      text: text,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Function Name: _stopVoiceGuide
  // Description: Stops spoken guidance, including a guide whose text is still loading, and clears the speaking state.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when playback has been asked to stop.
  Future<void> _stopVoiceGuide() async {
    await _requestVoiceGuide.stop();
    if (mounted) {
      // Function Name: _stopVoiceGuide.setState callback
      // Description: Updates the local input or request state for medication details with indications, dosage, precautions, and read-aloud controls: `_isSpeaking = false`.
      // Parameters:
      // - None.
      // Returns: No payload; applies the captured state changes.
      setState(() => _isSpeaking = false);
    }
  }

  // Function Name: _handleTtsButtonPressed
  // Description: Starts or stops spoken guidance and clears speaking state on completion or failure.
  // Parameters:
  // - None.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _handleTtsButtonPressed() async {
    if (_isSpeaking) {
      await _stopVoiceGuide();
      return;
    }

    // Function Name: _handleTtsButtonPressed.setState callback
    // Description: Updates the local input or request state for medication details with indications, dosage, precautions, and read-aloud controls: `_isSpeaking = true`.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
    setState(() => _isSpeaking = true);
    try {
      await _requestVoiceGuide.requestVoiceGuide(
        medicationDetail: widget.medicationDetail,
        userSetting: widget.userSetting,
        // Function Name: _handleTtsButtonPressed.onComplete callback
        // Description: Connects medication details with indications, dosage, precautions, and read-aloud controls to the captured operation `setState(() => _isSpeaking = false)`.
        // Parameters:
        // - None.
        // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
        onComplete: () {
          if (mounted) {
            // Function Name: _handleTtsButtonPressed.setState callback
            // Description: Updates the local input or request state for medication details with indications, dosage, precautions, and read-aloud controls: `_isSpeaking = false`.
            // Parameters:
            // - None.
            // Returns: No payload; applies the captured state changes.
            setState(() => _isSpeaking = false);
          }
        },
      );
    } catch (_) {
      if (mounted) {
        // Function Name: _handleTtsButtonPressed.setState callback
        // Description: Updates the local input or request state for medication details with indications, dosage, precautions, and read-aloud controls: `_isSpeaking = false`.
        // Parameters:
        // - None.
        // Returns: No payload; applies the captured state changes.
        setState(() => _isSpeaking = false);
      }
    }
  }
}

// 클래스명: _MedicationHeroCard
// 역할: 약품 대표 이미지와 표시 이름을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약품 대표 이미지와 표시 이름 위젯을 구성한다.
// 속성:
// - medicationDetail (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
// - displayName (String): 사용자에게 표시할 약품 또는 계정 이름.
// - language (String): 화면 문구를 선택할 언어 코드.
class _MedicationHeroCard extends StatelessWidget {
  final MedicationDetail medicationDetail;
  final String displayName;
  final String language;

  // 함수이름: _MedicationHeroCard
  // 함수역할: 약품 대표 이미지와 표시 이름에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medicationDetail (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
  // - displayName (String): 사용자에게 표시할 약품 또는 계정 이름.
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _MedicationHeroCard 인스턴스.
  const _MedicationHeroCard({
    required this.medicationDetail,
    required this.displayName,
    required this.language,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약품 대표 이미지와 표시 이름 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약품 대표 이미지와 표시 이름에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 226),
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 25),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: MedBuddyRadii.largeCard,
      ),
      child: Column(
        children: [
          _MedicationImageBox(
            medicationDetail: medicationDetail,
            displayName: displayName,
            language: language,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.medication_rounded,
                color: MedBuddyColors.primary,
                size: 22,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  displayName,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// 클래스명: _MedicationImageBox
// 역할: 확대 가능한 로컬·네트워크 약 사진과 실패 대체 표시를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 확대 가능한 로컬·네트워크 약 사진과 실패 대체 표시 위젯을 구성한다.
// 속성:
// - medicationDetail (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
// - displayName (String): 사용자에게 표시할 약품 또는 계정 이름.
// - language (String): 화면 문구를 선택할 언어 코드.
class _MedicationImageBox extends StatelessWidget {
  final MedicationDetail medicationDetail;
  final String displayName;
  final String language;

  // 함수이름: _MedicationImageBox
  // 함수역할: 확대 가능한 로컬·네트워크 약 사진과 실패 대체 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medicationDetail (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
  // - displayName (String): 사용자에게 표시할 약품 또는 계정 이름.
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _MedicationImageBox 인스턴스.
  const _MedicationImageBox({
    required this.medicationDetail,
    required this.displayName,
    required this.language,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 확대 가능한 로컬·네트워크 약 사진과 실패 대체 표시 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 확대 가능한 로컬·네트워크 약 사진과 실패 대체 표시에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final normalizedImageUrl = safeMedicationImageUrl(
      medicationDetail.imageUrl,
    );
    final localImageFile = medicationDetail.localImagePath.trim().isEmpty
        ? null
        : File(medicationDetail.localImagePath.trim());
    final hasLocalImage = localImageFile?.existsSync() ?? false;
    final hasImage = hasLocalImage || normalizedImageUrl.isNotEmpty;
    // 88dp 상자에 맞춰 디코딩해 원본 크기 사진이 메모리를 차지하지 않게 한다. 가로로 긴 사진을 채워 그릴 때도 흐려지지 않도록 두 배 여유를 둔다.
    final imageCacheWidth =
        (88 * MediaQuery.devicePixelRatioOf(context) * 2).round();

    return Semantics(
      button: hasImage,
      label: hasImage
          ? (isEnglishLanguage(language)
                ? 'Enlarge $displayName image'
                : '$displayName 사진 확대')
          : null,
      child: InkWell(
        key: const Key('medication-detail-image-button'),
        borderRadius: MedBuddyRadii.card,
        onTap: hasImage
            // 함수이름: build.onTap callback
            // 함수역할: 확대 가능한 로컬·네트워크 약 사진과 실패 대체 표시에서 캡처된 작업 `MedicationImageViewer.show(context, medicationName: displayName, imageUrl: normalizedImageUrl, localImagePath: medicationDetail.localImagePath...`을 실행한다.
            // 매개변수:
            // - 없음.
            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
            ? () => MedicationImageViewer.show(
                context,
                medicationName: displayName,
                imageUrl: normalizedImageUrl,
                localImagePath: medicationDetail.localImagePath,
                language: language,
              )
            : null,
        child: Container(
          width: 112,
          height: 112,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: MedBuddyRadii.card,
            boxShadow: MedBuddyShadows.card,
          ),
          child: ClipRRect(
            borderRadius: MedBuddyRadii.control,
            child: !hasLocalImage && normalizedImageUrl.isEmpty
                ? const ColoredBox(
                    color: MedBuddyColors.divider,
                    child: Icon(
                      Icons.medication_outlined,
                      color: MedBuddyColors.textLight,
                      size: 42,
                    ),
                  )
                : hasLocalImage
                ? Image.file(
                    localImageFile!,
                    fit: BoxFit.cover,
                    cacheWidth: imageCacheWidth,
                    errorBuilder: _buildImageError,
                  )
                : Image.network(
                    normalizedImageUrl,
                    fit: BoxFit.cover,
                    cacheWidth: imageCacheWidth,
                    errorBuilder: _buildImageError,
                  ),
          ),
        ),
      ),
    );
  }

  // 함수이름: _buildImageError
  // 함수역할: 약 사진을 불러오지 못한 영역을 이미지 없음 아이콘으로 대체한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // - error (Object): 사용자 안내 또는 복구 분기에 사용할 실패 정보.
  // - stackTrace (StackTrace?): 이미지 로드 실패 지점의 선택적 호출 스택; 표시에는 사용하지 않음.
  // 반환값: 확대 가능한 로컬·네트워크 약 사진과 실패 대체 표시에 쓰는 위젯 트리.
  Widget _buildImageError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return const ColoredBox(
      color: MedBuddyColors.divider,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: MedBuddyColors.textLight,
        size: 38,
      ),
    );
  }
}

// 클래스명: _DetailQuestionSection
// 역할: 약 효능·복용법 질문 제목과 간추린 답변 목록을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약 효능·복용법 질문 제목과 간추린 답변 목록 위젯을 구성한다.
// 속성:
// - title (String): 화면·구역·항목에 표시할 제목.
// - values (List<String>): 표시·정리할 설명 또는 주의 문구 목록.
// - noInformation (String): 값이나 약품 정보를 제공할 수 없을 때 사용할 대체 문구.
class _DetailQuestionSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<String> values;
  final String noInformation;

  // 함수이름: _DetailQuestionSection
  // 함수역할: 질문 제목·선택 설명과 답변 목록의 표시 설정을 초기화한다.
  // 매개변수:
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - subtitle (String?): 등록된 복용 정보 등 답변의 성격을 구분하는 설명.
  // - values (List<String>): 표시·정리할 설명 또는 주의 문구 목록.
  // - noInformation (String): 값이나 약품 정보를 제공할 수 없을 때 사용할 대체 문구.
  // 반환값: 입력 설정이 반영된 _DetailQuestionSection 인스턴스.
  const _DetailQuestionSection({
    required this.title,
    this.subtitle,
    required this.values,
    required this.noInformation,
  });

  // 함수이름: build
  // 함수역할: 질문과 선택 설명 아래 모든 답변을 순서대로 표시한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약 효능·복용법 질문 제목과 간추린 답변 목록에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final visibleValues = values
        // 함수이름: build.map callback
        // 함수역할: 약 효능·복용법 질문 제목과 간추린 답변 목록의 변환값을 `_summaryValue(value, noInformation)` 규칙으로 계산한다.
        // 매개변수:
        // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
        // 반환값: 컬렉션 연산에 전달할 변환값.
        .map((value) => _summaryValue(value, noInformation))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: MedBuddyColors.textStrong,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Column(
          children: [
            for (int index = 0; index < visibleValues.length; index++) ...[
              _DetailValueTile(value: visibleValues[index]),
              if (index != visibleValues.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ],
    );
  }
}

// Class Name: _DetailValueTile
// Role: Represents an emphasized compact medication-information value.
// Responsibilities:
// - Composes an emphasized compact medication-information value using the display values and actions supplied by its parent.
// Attributes:
// - value (String): Input to validate, normalize, display, or pass through a selection callback.
class _DetailValueTile extends StatelessWidget {
  final String value;

  // 함수이름: _DetailValueTile
  // 함수역할: 간추린 약품 정보 한 줄의 강조 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 입력 설정이 반영된 _DetailValueTile 인스턴스.
  const _DetailValueTile({required this.value});

  // Function Name: build
  // Description: Renders an emphasized compact medication-information value from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for an emphasized compact medication-information value.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: MedBuddyRadii.control,
        border: Border.all(color: MedBuddyColors.divider),
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: MedBuddyColors.textStrong,
          fontSize: 14,
          height: 1.35,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// 클래스명: _DetailedDosageGuideCard
// 역할: 설정 언어별 상세 복용 가이드 목록을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 설정 언어별 상세 복용 가이드 목록 위젯을 구성한다.
// 속성:
// - medicationDetail (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
class _DetailedDosageGuideCard extends StatelessWidget {
  final MedicationDetail medicationDetail;
  final _MedicationDetailText text;

  // 함수이름: _DetailedDosageGuideCard
  // 함수역할: 설정 언어별 상세 복용 가이드 목록에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medicationDetail (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
  // - text (_MedicationDetailText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _DetailedDosageGuideCard 인스턴스.
  const _DetailedDosageGuideCard({
    required this.medicationDetail,
    required this.text,
  });

  // 함수이름: build
  // 함수역할: 복용 요약을 반복하지 않고 용법 원문 전체를 상세 가이드로 표시한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 설정 언어별 상세 복용 가이드 목록에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return _DetailListCard(
      title: text.detailedGuide,
      items: _uniqueNonEmptyValues([medicationDetail.usageMethod]),
      noInformation: text.noInformation,
    );
  }
}

// 클래스명: _MedicationRiskCard
// 역할: 중복을 제거한 경고·주의·상호작용·부작용 목록을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 중복을 제거한 경고·주의·상호작용·부작용 목록 위젯을 구성한다.
// 속성:
// - medicationDetail (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
class _MedicationRiskCard extends StatelessWidget {
  final MedicationDetail medicationDetail;
  final _MedicationDetailText text;

  // 함수이름: _MedicationRiskCard
  // 함수역할: 중복을 제거한 경고·주의·상호작용·부작용 목록에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medicationDetail (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
  // - text (_MedicationDetailText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _MedicationRiskCard 인스턴스.
  const _MedicationRiskCard({
    required this.medicationDetail,
    required this.text,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 중복을 제거한 경고·주의·상호작용·부작용 목록 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 중복을 제거한 경고·주의·상호작용·부작용 목록에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return _DetailListCard(
      title: text.risksAndSideEffects,
      items: _uniqueNonEmptyValues([
        medicationDetail.warning,
        medicationDetail.precaution,
        medicationDetail.interaction,
        medicationDetail.sideEffect,
      ]),
      useInsetSurface: true,
      noInformation: text.noInformation,
    );
  }
}

// 클래스명: _MedicationChecklistCard
// 역할: 보관법과 AI 안내를 묶은 복약 확인 목록을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 보관법과 AI 안내를 묶은 복약 확인 목록 위젯을 구성한다.
// 속성:
// - medicationDetail (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
class _MedicationChecklistCard extends StatelessWidget {
  final MedicationDetail medicationDetail;
  final _MedicationDetailText text;

  // 함수이름: _MedicationChecklistCard
  // 함수역할: 보관법과 AI 안내를 묶은 복약 확인 목록에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medicationDetail (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
  // - text (_MedicationDetailText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _MedicationChecklistCard 인스턴스.
  const _MedicationChecklistCard({
    required this.medicationDetail,
    required this.text,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 보관법과 AI 안내를 묶은 복약 확인 목록 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 보관법과 AI 안내를 묶은 복약 확인 목록에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return _DetailListCard(
      title: text.checklist,
      items: _uniqueNonEmptyValues([
        medicationDetail.storageMethod,
        medicationDetail.aiGuide,
      ]),
      noInformation: text.noInformation,
    );
  }
}

// 클래스명: _DetailListCard
// 역할: 제목과 빈 정보 대체 문구를 갖춘 약품 설명 목록을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 제목과 빈 정보 대체 문구를 갖춘 약품 설명 목록 위젯을 구성한다.
// 속성:
// - title (String): 화면·구역·항목에 표시할 제목.
// - items (List<String>): 표시·정리할 설명 또는 주의 문구 목록.
// - useInsetSurface (bool): 설명 목록을 내부 배경 면으로 감쌀지 여부.
class _DetailListCard extends StatelessWidget {
  final String title;
  final List<String> items;
  final bool useInsetSurface;
  final String noInformation;

  // 함수이름: _DetailListCard
  // 함수역할: 제목과 빈 정보 대체 문구를 갖춘 약품 설명 목록에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - items (List<String>): 표시·정리할 설명 또는 주의 문구 목록.
  // - useInsetSurface (bool): 설명 목록을 내부 배경 면으로 감쌀지 여부.
  // - noInformation (String): 값이나 약품 정보를 제공할 수 없을 때 사용할 대체 문구.
  // 반환값: 입력 설정이 반영된 _DetailListCard 인스턴스.
  const _DetailListCard({
    required this.title,
    required this.items,
    this.useInsetSurface = false,
    required this.noInformation,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 제목과 빈 정보 대체 문구를 갖춘 약품 설명 목록 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 제목과 빈 정보 대체 문구를 갖춘 약품 설명 목록에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final visibleItems = items.isEmpty ? [noInformation] : items;
    final itemList = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int index = 0; index < visibleItems.length; index++) ...[
          Text(
            visibleItems[index],
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          if (index != visibleItems.length - 1) const SizedBox(height: 10),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        color: MedBuddyColors.surfaceSubtle,
        borderRadius: MedBuddyRadii.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          if (useInsetSurface)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: MedBuddyRadii.control,
              ),
              child: itemList,
            )
          else
            itemList,
        ],
      ),
    );
  }
}

// Function Name: _summaryValues
// Description: Splits indication text at delimiters and sentence boundaries, compacts each part, and supplies a fallback for empty input.
// Parameters:
// - value (String): Input to validate, normalize, display, or pass through a selection callback.
// - noInformation (String): Fallback wording when a value or medication information is unavailable.
// Returns: List<String>: Normalized display wording or selected dose-slot keys.
List<String> _summaryValues(String value, String noInformation) {
  final normalizedValue = value.trim();
  if (normalizedValue.isEmpty) {
    return [noInformation];
  }

  final values = normalizedValue
      .split(RegExp(r'[,/;·\n]+|[.!?。]+\s*|\s+(?:또한|그리고|아울러)\s+'))
      .map(_compactIndicationLabel)
      // Function Name: _summaryValues.where callback
      // Description: Checks the collection condition `item.isNotEmpty` for medication indications, dosage, precautions, and spoken guidance.
      // Parameters:
      // - item (inferred by callback contract): Medication data to display, transform, save, or compare.
      // Returns: Boolean predicate result for the supplied item.
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  final fallback = _compactIndicationLabel(normalizedValue);
  return values.isEmpty ? [fallback.isEmpty ? noInformation : fallback] : values;
}

// Function Name: _compactIndicationLabel
// Description: Compacts indication text for summary tiles by removing repetitive Korean prefixes, endings, and punctuation without changing the original speech content.
// Parameters:
// - value (String): Input to validate, normalize, display, or pass through a selection callback.
// Returns: The formatted display text or identifier described above.
String _compactIndicationLabel(String value) {
  var label = value.trim();
  label = label.replaceFirst(RegExp(r'^(?:또한|그리고|아울러)\s*'), '');
  label = label.replaceFirst(RegExp(r'^(?:이\s*약(?:은|이)?|본\s*약은)\s*'), '');
  label = label.replaceFirst(
    RegExp(
      r'\s*(?:의\s*)?(?:치료|완화|개선)?\s*(?:에|을\s*위해)?\s*'
      r'(?:사용합니다|사용됩니다|쓰입니다)\.?$',
    ),
    '',
  );
  label = label.replaceFirst(
    RegExp(
      r'\s*(?:을|를)\s*'
      r'(?:치료|완화|개선|경감|예방)'
      r'(?:합니다|해줍니다|하는\s*데\s*사용(?:합니다|됩니다))?\.?$',
    ),
    '',
  );
  label = label.replaceFirst(
    RegExp(r'\s*(?:을|를)\s*풀어주(?:고|며|는\s*데\s*사용(?:합니다|됩니다))\.?$'),
    '',
  );
  label = label.replaceFirst(RegExp(r'\s*(?:에|에서)\s*효과가\s*있습니다\.?$'), '');
  return label.replaceFirst(RegExp(r'[.!?。]+$'), '').trim();
}

// 함수이름: _summaryValue
// 함수역할: 앞뒤 공백을 제거하고 빈 정보는 호출자가 지정한 문구로 대체한다.
// 매개변수:
// - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
// - noInformation (String): 값이나 약품 정보를 제공할 수 없을 때 사용할 대체 문구.
// 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
String _summaryValue(String value, String noInformation) {
  final normalizedValue = value.trim();
  return normalizedValue.isEmpty ? noInformation : normalizedValue;
}

// Function Name: _uniqueNonEmptyValues
// Description: Removes empty and duplicate values while preserving first-occurrence order.
// Parameters:
// - values (List<String>): Information or caution values to display or normalize.
// Returns: List<String>: Normalized display wording or selected dose-slot keys.
List<String> _uniqueNonEmptyValues(List<String> values) {
  final uniqueValues = <String>{};
  for (final value in values) {
    final normalizedValue = value.trim();
    if (normalizedValue.isNotEmpty) {
      uniqueValues.add(normalizedValue);
    }
  }
  return uniqueValues.toList(growable: false);
}

// 클래스명: _TtsButton
// 역할: 읽어주기 시작·중지 상태와 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 읽어주기 시작·중지 상태와 명령 위젯을 구성한다.
// 속성:
// - isSpeaking (bool): 읽어주기가 현재 재생 중인지 여부.
// - onPressed (Future<void> Function()): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _TtsButton extends StatelessWidget {
  final bool isSpeaking;
  final Future<void> Function() onPressed;
  final _MedicationDetailText text;

  // 함수이름: _TtsButton
  // 함수역할: 읽어주기 시작·중지 상태와 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - isSpeaking (bool): 읽어주기가 현재 재생 중인지 여부.
  // - onPressed (Future<void> Function()): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // - text (_MedicationDetailText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _TtsButton 인스턴스.
  const _TtsButton({
    required this.isSpeaking,
    required this.onPressed,
    required this.text,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 읽어주기 시작·중지 상태와 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 읽어주기 시작·중지 상태와 명령에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up),
      label: Text(isSpeaking ? text.stopReading : text.readAloud),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        textStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// 클래스명: _MedicationDetailText
// 역할: 약품 효능, 복용법, 주의사항 및 음성 안내에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 약품 효능, 복용법, 주의사항 및 음성 안내에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - isEnglish (bool): 영어 문구를 선택할지 여부; false이면 한국어.
class _MedicationDetailText {
  final bool isEnglish;

  // 함수이름: _MedicationDetailText
  // 함수역할: 약품 효능, 복용법, 주의사항 및 음성 안내에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _MedicationDetailText 인스턴스.
  _MedicationDetailText(String language)
    : isEnglish = isEnglishLanguage(language);

  // 함수이름: title
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 상세정보" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get title => isEnglish ? 'Medication Details' : '약 상세정보';
  // 함수이름: back
  // 함수역할: 현재 언어와 입력값에 맞춰 "뒤로가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get back => isEnglish ? 'Back' : '뒤로가기';
  // 함수이름: efficacyQuestion
  // 함수역할: 현재 언어와 입력값에 맞춰 "이 약은 어디가 좋아지나요?" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get efficacyQuestion =>
      isEnglish ? 'What is this medication for?' : '이 약은 어디가 좋아지나요?';
  // 함수이름: dosageQuestion
  // 함수역할: 현재 언어와 입력값에 맞춰 "어떻게 먹나요?" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get dosageQuestion => isEnglish ? 'How should I take it?' : '어떻게 먹나요?';
  // 함수이름: registeredDosage
  // 함수역할: 출처를 추측하지 않고 등록된 복용값임을 구분한다.
  // 매개변수: 없음. 반환값: 언어별 복용 정보 설명.
  String get registeredDosage =>
      isEnglish ? 'Registered dosage information' : '등록된 복용 정보';
  // 함수이름: detailedGuide
  // 함수역할: 현재 언어와 입력값에 맞춰 "상세 복용 가이드" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get detailedGuide =>
      isEnglish ? 'Detailed medication guide' : '상세 복용 가이드';
  // 함수이름: risksAndSideEffects
  // 함수역할: 현재 언어와 입력값에 맞춰 "주요 주의사항 및 부작용" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get risksAndSideEffects =>
      isEnglish ? 'Important warnings and side effects' : '주요 주의사항 및 부작용';
  // 함수이름: checklist
  // 함수역할: 현재 언어와 입력값에 맞춰 "간편한 가이드 (Checklist)" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get checklist => isEnglish ? 'Quick checklist' : '간편한 가이드 (Checklist)';
  // 함수이름: noInformation
  // 함수역할: 현재 언어와 입력값에 맞춰 "정보 없음" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noInformation => isEnglish ? 'No information' : '정보 없음';
  // 함수이름: stopReading
  // 함수역할: 현재 언어와 입력값에 맞춰 "읽기 중지" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get stopReading => isEnglish ? 'Stop reading' : '읽기 중지';
  // 함수이름: readAloud
  // 함수역할: 현재 언어와 입력값에 맞춰 "큰 소리로 읽어주세요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get readAloud => isEnglish ? 'Read aloud' : '큰 소리로 읽어주세요';
}
