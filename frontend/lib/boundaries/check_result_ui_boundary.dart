// File Name: check_result_ui_boundary.dart
// Role: UI boundaries and helpers for prescription analysis results and individual or bulk schedule saving.

import 'package:flutter/material.dart';

import '../entities/analyzed_medication_entity.dart';
import '../entities/prescription_change_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import 'prescription_change_radar_ui_boundary.dart';

// 파일명: check_result_ui_boundary.dart
// 역할: 공공데이터 분석이 끝난 처방전 결과 목록 화면을 구성한다.

// Class Name: CheckResultUI
// Role: Represents analyzed medications and individual or bulk save state.
// Responsibilities:
// - Displays the analyzed medication count and each schedule.
// - Shows per-item saving, bulk save, and disabled controls for saved items.
// - Reports save outcomes through a Snackbar.
// Attributes:
// - analyzedMedicationList (List<AnalyzedMedication>): Prescription analysis results containing medication details and schedules.
// - prescriptionChangeRadar (PrescriptionChangeRadar?): Comparison status and changes against a previous prescription.
// - isPrescriptionChangeLoading (bool): Whether the associated save, analysis, or medication update is in progress.
// - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
class CheckResultUI extends StatelessWidget {
  final List<AnalyzedMedication> analyzedMedicationList;
  final PrescriptionChangeRadar? prescriptionChangeRadar;
  final bool isPrescriptionChangeLoading;
  final UserSetting userSetting;
  final String Function() statusMessageProvider;
  final int? savingMedicationIndex;
  final Set<int> completedMedicationSaveIndexes;
  final bool isAllMedicationSaving;
  final VoidCallback? onCloseRequested;
  final VoidCallback? onTodayScheduleRequested;
  final VoidCallback? onSavedMedicationRequested;
  final VoidCallback? onHomeRequested;
  final Future<bool> Function() onAllMedicationSaveRequested;
  final Future<bool> Function(
    AnalyzedMedication analyzedMedication,
    int medicationIndex,
  )
  onMedicationSaveRequested;

  // 함수이름: CheckResultUI
  // 함수역할: 분석 약 목록과 개별·전체 저장 상태에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - key (Key?): 위젯을 구분하고 상태를 유지할 식별 키.
  // - analyzedMedicationList (List<AnalyzedMedication>): 약 상세와 일정을 함께 가진 처방 분석 결과 목록.
  // - prescriptionChangeRadar (PrescriptionChangeRadar?): 이전 처방과의 비교 상태·변화 목록.
  // - isPrescriptionChangeLoading (bool): 해당 저장·분석·복약 갱신 요청이 진행 중인지 여부.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - statusMessageProvider (String Function()): 작업 후 최신 상태 안내를 읽는 함수.
  // - savingMedicationIndex (int?): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
  // - completedMedicationSaveIndexes (Set<int>): 이미 저장을 완료한 분석 결과의 인덱스 집합.
  // - isAllMedicationSaving (bool): 해당 저장·분석·복약 갱신 요청이 진행 중인지 여부.
  // - onCloseRequested (VoidCallback?): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
  // - onTodayScheduleRequested (VoidCallback?): 오늘 복약 일정 화면을 여는 콜백.
  // - onSavedMedicationRequested (VoidCallback?): 저장 복약함 화면을 여는 콜백.
  // - onHomeRequested (VoidCallback?): 홈 화면으로 이동할 콜백.
  // - onAllMedicationSaveRequested (Future<bool> Function()): 선택한 약품 또는 분석 결과를 일괄 저장할 콜백.
  // - onMedicationSaveRequested (Future<bool> Function(AnalyzedMedication analyzedMedication, int medicationIndex)): 검증한 약품과 복약 정보를 저장할 콜백.
  // 반환값: 입력 설정이 반영된 CheckResultUI 인스턴스.
  const CheckResultUI({
    super.key,
    required this.analyzedMedicationList,
    this.prescriptionChangeRadar,
    this.isPrescriptionChangeLoading = false,
    required this.userSetting,
    required this.statusMessageProvider,
    required this.savingMedicationIndex,
    required this.completedMedicationSaveIndexes,
    required this.isAllMedicationSaving,
    required this.onCloseRequested,
    this.onTodayScheduleRequested,
    this.onSavedMedicationRequested,
    this.onHomeRequested,
    required this.onAllMedicationSaveRequested,
    required this.onMedicationSaveRequested,
  });

  // Function Name: build
  // Description: Renders analyzed medications and individual or bulk save state from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for analyzed medications and individual or bulk save state.
  @override
  Widget build(BuildContext context) {
    final text = _ResultText(userSetting.language);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _ResultHeader(
              title: text.title,
              backTooltip: text.back,
              onCloseRequested: onCloseRequested,
            ),
            _AnalysisSummary(
              count: analyzedMedicationList.length,
              text: text,
              userSetting: userSetting,
            ),
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    padding: const EdgeInsets.fromLTRB(40, 10, 40, 126),
                    itemCount:
                        analyzedMedicationList.length +
                        (prescriptionChangeRadar != null ||
                                isPrescriptionChangeLoading
                            ? 1
                            : 0),
                    // Function Name: build.itemBuilder callback
                    // Description: Composes analyzed medications and individual or bulk save state with the current parent constraints for the active layout.
                    // Parameters:
                    // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
                    // - index (int): Zero-based position of the target medication, photo, or row.
                    // Returns: Widget subtree for the described layout or fallback.
                    itemBuilder: (context, index) {
                      final hasRadarSlot =
                          prescriptionChangeRadar != null ||
                          isPrescriptionChangeLoading;
                      if (hasRadarSlot && index == 0) {
                        if (isPrescriptionChangeLoading) {
                          return PrescriptionChangeRadarLoadingUI(
                            userSetting: userSetting,
                          );
                        }
                        return PrescriptionChangeRadarUI(
                          radar: prescriptionChangeRadar!,
                          userSetting: userSetting,
                        );
                      }

                      final medicationIndex = hasRadarSlot ? index - 1 : index;
                      final analyzedMedication =
                          analyzedMedicationList[medicationIndex];
                      return _MedicationResultCard(
                        analyzedMedication: analyzedMedication,
                        text: text,
                        userSetting: userSetting,
                        isMedicationSaving:
                            savingMedicationIndex == medicationIndex,
                        isMedicationSaved: completedMedicationSaveIndexes
                            .contains(medicationIndex),
                        isAllMedicationSaving:
                            isAllMedicationSaving ||
                            savingMedicationIndex != null,
                        // 함수이름: build.onMedicationSaveRequested callback
                        // 함수역할: 저장 완료 시트를 열고 선택한 목적지로 이동하기 전에 시트를 닫는다.
                        // 매개변수:
                        // - 없음.
                        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                        onMedicationSaveRequested: () async {
                          final success = await onMedicationSaveRequested(
                            analyzedMedication,
                            medicationIndex,
                          );
                          if (!context.mounted) {
                            return;
                          }
                          final allSaved =
                              completedMedicationSaveIndexes.length >=
                              analyzedMedicationList.length;
                          if (success && allSaved) {
                            await _showSaveCompletedSheet(context, text);
                            return;
                          }
                          _showSaveResultMessage(context, success);
                        },
                      );
                    },
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _BulkSaveButton(
                      text: text,
                      userSetting: userSetting,
                      isSaving:
                          isAllMedicationSaving ||
                          savingMedicationIndex != null,
                      isCompleted:
                          completedMedicationSaveIndexes.length >=
                          analyzedMedicationList.length,
                      // 함수이름: build.onPressed callback
                      // 함수역할: 저장 완료 시트를 열고 선택한 목적지로 이동하기 전에 시트를 닫는다.
                      // 매개변수:
                      // - 없음.
                      // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                      onPressed: () async {
                        final success = await onAllMedicationSaveRequested();
                        if (!context.mounted) {
                          return;
                        }
                        if (success) {
                          await _showSaveCompletedSheet(context, text);
                          return;
                        }
                        _showSaveResultMessage(context, false);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 함수이름: _showSaveResultMessage
  // 함수역할: 현재 저장 결과 문구를 성공·실패 색상으로 2초간 표시한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // - success (bool): 직전 저장·조회·변경 요청의 성공 여부.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _showSaveResultMessage(BuildContext context, bool success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(statusMessageProvider()),
        backgroundColor: success
            ? const Color(0xFF059669)
            : const Color(0xFFDC2626),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 함수이름: _showSaveCompletedSheet
  // 함수역할: 저장 완료 시트를 열고 선택한 목적지로 이동하기 전에 시트를 닫는다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // - text (_ResultText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _showSaveCompletedSheet(BuildContext context, _ResultText text) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // 함수이름: _showSaveCompletedSheet.builder callback
      // 함수역할: 분석 약 목록과 개별·전체 저장 상태에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - sheetContext (BuildContext): 현재 대화상자·하단 시트의 화면 종료와 테마 참조 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (sheetContext) => _SaveCompletedSheet(
        text: text,
        userSetting: userSetting,
        onTodayScheduleRequested: onTodayScheduleRequested == null
            ? null
            // 함수이름: _showSaveCompletedSheet.onTodayScheduleRequested callback
            // 함수역할: `Navigator.pop(sheetContext)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            : () {
                Navigator.pop(sheetContext);
                onTodayScheduleRequested!.call();
              },
        onSavedMedicationRequested: onSavedMedicationRequested == null
            ? null
            // 함수이름: _showSaveCompletedSheet.onSavedMedicationRequested callback
            // 함수역할: `Navigator.pop(sheetContext)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            : () {
                Navigator.pop(sheetContext);
                onSavedMedicationRequested!.call();
              },
        onHomeRequested: onHomeRequested == null
            ? null
            // 함수이름: _showSaveCompletedSheet.onHomeRequested callback
            // 함수역할: `Navigator.pop(sheetContext)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
            // 매개변수:
            // - 없음.
            // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
            : () {
                Navigator.pop(sheetContext);
                onHomeRequested!.call();
              },
      ),
    );
  }
}

// 클래스명: _SaveCompletedSheet
// 역할: 저장 완료 후 오늘 일정·복약함·홈 이동을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 저장 완료 후 오늘 일정·복약함·홈 이동 위젯을 구성한다.
// 속성:
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - onTodayScheduleRequested (VoidCallback?): 오늘 복약 일정 화면을 여는 콜백.
// - onSavedMedicationRequested (VoidCallback?): 저장 복약함 화면을 여는 콜백.
// - onHomeRequested (VoidCallback?): 홈 화면으로 이동할 콜백.
class _SaveCompletedSheet extends StatelessWidget {
  final _ResultText text;
  final UserSetting userSetting;
  final VoidCallback? onTodayScheduleRequested;
  final VoidCallback? onSavedMedicationRequested;
  final VoidCallback? onHomeRequested;

  // 함수이름: _SaveCompletedSheet
  // 함수역할: 저장 완료 후 오늘 일정·복약함·홈 이동에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_ResultText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - onTodayScheduleRequested (VoidCallback?): 오늘 복약 일정 화면을 여는 콜백.
  // - onSavedMedicationRequested (VoidCallback?): 저장 복약함 화면을 여는 콜백.
  // - onHomeRequested (VoidCallback?): 홈 화면으로 이동할 콜백.
  // 반환값: 입력 설정이 반영된 _SaveCompletedSheet 인스턴스.
  const _SaveCompletedSheet({
    required this.text,
    required this.userSetting,
    required this.onTodayScheduleRequested,
    required this.onSavedMedicationRequested,
    required this.onHomeRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 저장 완료 후 오늘 일정·복약함·홈 이동 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 저장 완료 후 오늘 일정·복약함·홈 이동에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        26,
        24,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: MedBuddyColors.primary,
            size: 58,
          ),
          const SizedBox(height: 12),
          Text(
            text.saveCompletedTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MedBuddyColors.textStrong,
              fontSize: 22 * scale,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text.saveCompletedDescription,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 14 * scale,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          if (onTodayScheduleRequested != null)
            FilledButton.icon(
              onPressed: onTodayScheduleRequested,
              icon: const Icon(Icons.event_available_outlined),
              label: Text(text.openTodaySchedule),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                backgroundColor: MedBuddyColors.primary,
              ),
            ),
          if (onSavedMedicationRequested != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onSavedMedicationRequested,
              icon: const Icon(Icons.medication_outlined),
              label: Text(text.openSavedMedication),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
              ),
            ),
          ],
          if (onHomeRequested != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onHomeRequested,
              child: Text(text.returnHome),
            ),
          ],
        ],
      ),
    );
  }
}

// 클래스명: _ResultHeader
// 역할: 처방 분석 결과 제목과 닫기 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 처방 분석 결과 제목과 닫기 명령 위젯을 구성한다.
// 속성:
// - title (String): 화면·구역·항목에 표시할 제목.
// - backTooltip (String): 아이콘의 동작을 설명할 도움말·접근성 문구.
// - onCloseRequested (VoidCallback?): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
class _ResultHeader extends StatelessWidget {
  final String title;
  final String backTooltip;
  final VoidCallback? onCloseRequested;

  // 함수이름: _ResultHeader
  // 함수역할: 처방 분석 결과 제목과 닫기 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - title (String): 화면·구역·항목에 표시할 제목.
  // - backTooltip (String): 아이콘의 동작을 설명할 도움말·접근성 문구.
  // - onCloseRequested (VoidCallback?): 이전 단계로 이동하거나 현재 화면을 닫을 때 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _ResultHeader 인스턴스.
  const _ResultHeader({
    required this.title,
    required this.backTooltip,
    required this.onCloseRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 처방 분석 결과 제목과 닫기 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 처방 분석 결과 제목과 닫기 명령에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 94),
      width: double.infinity,
      color: MedBuddyColors.topBar,
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: backTooltip,
            onPressed: onCloseRequested,
            icon: Icon(
              Icons.arrow_back,
              color: onCloseRequested == null ? Colors.white54 : Colors.white,
              size: 31,
            ),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

// Class Name: _AnalysisSummary
// Role: Represents a summary of analyzed medications ready to save.
// Responsibilities:
// - Composes a summary of analyzed medications ready to save using the display values and actions supplied by its parent.
// Attributes:
// - count (int): Item count or ordinal number used in wording or a list.
// - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
class _AnalysisSummary extends StatelessWidget {
  final int count;
  final _ResultText text;
  final UserSetting userSetting;

  // 함수이름: _AnalysisSummary
  // 함수역할: 저장 가능한 분석 약품 수 요약에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // - text (_ResultText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // 반환값: 입력 설정이 반영된 _AnalysisSummary 인스턴스.
  const _AnalysisSummary({
    required this.count,
    required this.text,
    required this.userSetting,
  });

  // Function Name: build
  // Description: Renders a summary of analyzed medications ready to save from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for a summary of analyzed medications ready to save.
  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.successBorder, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.08),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: MedBuddyColors.mint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: MedBuddyColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.complete,
                  style: TextStyle(
                    color: MedBuddyColors.primaryDark,
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  text.summary(count),
                  style: TextStyle(
                    color: MedBuddyColors.textMuted,
                    fontSize: 14 * scale,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Class Name: _BulkSaveButton
// Role: Represents the bulk-save action with busy and completed states preventing duplicate requests.
// Responsibilities:
// - Composes the bulk-save action with busy and completed states preventing duplicate requests using the display values and actions supplied by its parent.
// Attributes:
// - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
// - isSaving (bool): Whether the associated save, analysis, or medication update is in progress.
// - isCompleted (bool): Completion state of the dose or save operation.
// - onPressed (Future<void> Function()): Callback executing the item's documented primary action.
class _BulkSaveButton extends StatelessWidget {
  final _ResultText text;
  final UserSetting userSetting;
  final bool isSaving;
  final bool isCompleted;
  final Future<void> Function() onPressed;

  // 함수이름: _BulkSaveButton
  // 함수역할: 중복 요청을 막는 전체 저장·완료 상태에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_ResultText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - isSaving (bool): 해당 저장·분석·복약 갱신 요청이 진행 중인지 여부.
  // - isCompleted (bool): 복약 또는 저장 작업의 완료 상태.
  // - onPressed (Future<void> Function()): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _BulkSaveButton 인스턴스.
  const _BulkSaveButton({
    required this.text,
    required this.userSetting,
    required this.isSaving,
    required this.isCompleted,
    required this.onPressed,
  });

  // Function Name: build
  // Description: Renders the bulk-save action with busy and completed states preventing duplicate requests from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the bulk-save action with busy and completed states preventing duplicate requests.
  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        40,
        22,
        40,
        MediaQuery.of(context).padding.bottom + 23,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: MedBuddyColors.divider)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          // 함수이름: build.onPressed callback
          // 함수역할: 중복 요청을 막는 전체 저장·완료 상태에서 캡처된 작업 `onPressed()`을 실행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onPressed: isSaving || isCompleted ? null : () async => onPressed(),
          icon: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  isCompleted ? Icons.check_circle_outline : Icons.done_all,
                  size: 22,
                ),
          label: Text(
            isCompleted
                ? text.allSaved
                : isSaving
                ? text.savingAll
                : text.saveAll,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: MedBuddyColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF9CA3AF),
            disabledForegroundColor: Colors.white,
            minimumSize: const Size.fromHeight(66),
            shape: RoundedRectangleBorder(
              borderRadius: MedBuddyRadii.largeCard,
            ),
            textStyle: TextStyle(
              fontSize: 22 * scale,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

// 클래스명: _MedicationResultCard
// 역할: 약 한 건의 복용량·횟수·기간과 개별 저장을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약 한 건의 복용량·횟수·기간과 개별 저장 위젯을 구성한다.
// 속성:
// - analyzedMedication (AnalyzedMedication): 표시·변환·저장·비교할 약품 데이터.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - isMedicationSaving (bool): 해당 저장·분석·복약 갱신 요청이 진행 중인지 여부.
// - isMedicationSaved (bool): 복약 또는 저장 작업의 완료 상태.
class _MedicationResultCard extends StatelessWidget {
  final AnalyzedMedication analyzedMedication;
  final _ResultText text;
  final UserSetting userSetting;
  final bool isMedicationSaving;
  final bool isMedicationSaved;
  final bool isAllMedicationSaving;
  final Future<void> Function() onMedicationSaveRequested;

  // 함수이름: _MedicationResultCard
  // 함수역할: 약 한 건의 복용량·횟수·기간과 개별 저장에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - analyzedMedication (AnalyzedMedication): 표시·변환·저장·비교할 약품 데이터.
  // - text (_ResultText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - isMedicationSaving (bool): 해당 저장·분석·복약 갱신 요청이 진행 중인지 여부.
  // - isMedicationSaved (bool): 복약 또는 저장 작업의 완료 상태.
  // - isAllMedicationSaving (bool): 해당 저장·분석·복약 갱신 요청이 진행 중인지 여부.
  // - onMedicationSaveRequested (Future<void> Function()): 검증한 약품과 복약 정보를 저장할 콜백.
  // 반환값: 입력 설정이 반영된 _MedicationResultCard 인스턴스.
  const _MedicationResultCard({
    required this.analyzedMedication,
    required this.text,
    required this.userSetting,
    required this.isMedicationSaving,
    required this.isMedicationSaved,
    required this.isAllMedicationSaving,
    required this.onMedicationSaveRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약 한 건의 복용량·횟수·기간과 개별 저장 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약 한 건의 복용량·횟수·기간과 개별 저장에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final schedule = analyzedMedication.schedule;
    final scale = userSetting.contentTextScale;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.largeCard,
        border: Border.all(color: MedBuddyColors.cardBorder, width: 2),
        boxShadow: MedBuddyShadows.card,
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            decoration: const BoxDecoration(
              color: MedBuddyColors.successSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(color: MedBuddyColors.mint, width: 2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: MedBuddyColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.medication_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    analyzedMedication.displayNameForLanguage(text.language),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 22 * scale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _MedicationSaveIconButton(
                  text: text,
                  isMedicationSaving: isMedicationSaving,
                  isMedicationSaved: isMedicationSaved,
                  isAllMedicationSaving: isAllMedicationSaving,
                  onPressed: onMedicationSaveRequested,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              children: [
                _DoseInfoRow(
                  icon: Icons.medication_liquid_outlined,
                  label: text.dose,
                  value: _displayValue(
                    schedule.dosageLabelForLanguage(text.language),
                  ),
                  userSetting: userSetting,
                ),
                const SizedBox(height: 14),
                _DoseInfoRow(
                  icon: Icons.schedule_outlined,
                  label: text.frequency,
                  value: _displayValue(
                    schedule.dailyFrequencyLabelForLanguage(text.language),
                  ),
                  userSetting: userSetting,
                ),
                const SizedBox(height: 14),
                _DoseInfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: text.duration,
                  value: _displayValue(
                    schedule.durationLabelForLanguage(text.language),
                  ),
                  userSetting: userSetting,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 함수이름: _displayValue
  // 함수역할: 빈 값을 정보 없음 문구로 대체하고 지정된 최대 길이를 넘으면 말줄임한다.
  // 매개변수:
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // - maxLength (int?): 허용할 최대 항목 수 또는 문자열 길이.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _displayValue(String value, {int? maxLength}) {
    final textValue = value.trim().isEmpty ? text.noInformation : value.trim();
    if (maxLength == null || textValue.length <= maxLength) {
      return textValue;
    }
    return '${textValue.substring(0, maxLength)}...';
  }
}

// Class Name: _MedicationSaveIconButton
// Role: Represents the medication-save icon disabled during saving or after completion.
// Responsibilities:
// - Composes the medication-save icon disabled during saving or after completion using the display values and actions supplied by its parent.
// Attributes:
// - isMedicationSaving (bool): Whether the associated save, analysis, or medication update is in progress.
// - isMedicationSaved (bool): Completion state of the dose or save operation.
// - isAllMedicationSaving (bool): Whether the associated save, analysis, or medication update is in progress.
// - onPressed (Future<void> Function()): Callback executing the item's documented primary action.
class _MedicationSaveIconButton extends StatelessWidget {
  final _ResultText text;
  final bool isMedicationSaving;
  final bool isMedicationSaved;
  final bool isAllMedicationSaving;
  final Future<void> Function() onPressed;

  // Function Name: _MedicationSaveIconButton
  // Description: Initializes the medication-save icon disabled during saving or after completion with the supplied configuration.
  // Parameters:
  // - text (_ResultText): Localized labels used by this section.
  // - isMedicationSaving (bool): Whether the associated save, analysis, or medication update is in progress.
  // - isMedicationSaved (bool): Completion state of the dose or save operation.
  // - isAllMedicationSaving (bool): Whether the associated save, analysis, or medication update is in progress.
  // - onPressed (Future<void> Function()): Callback executing the item's documented primary action.
  // Returns: Initialized _MedicationSaveIconButton instance.
  const _MedicationSaveIconButton({
    required this.text,
    required this.isMedicationSaving,
    required this.isMedicationSaved,
    required this.isAllMedicationSaving,
    required this.onPressed,
  });

  // Function Name: build
  // Description: Renders the medication-save icon disabled during saving or after completion from the current configuration and state.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // Returns: Widget tree for the medication-save icon disabled during saving or after completion.
  @override
  Widget build(BuildContext context) {
    final isDisabled =
        isMedicationSaving || isMedicationSaved || isAllMedicationSaving;

    return Tooltip(
      message: isMedicationSaved ? text.saved : text.saveSchedule,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
        style: IconButton.styleFrom(
          foregroundColor: MedBuddyColors.primary,
          disabledForegroundColor: MedBuddyColors.textLight,
          backgroundColor: Colors.transparent,
          shape: const CircleBorder(),
        ),
        // Function Name: build.onPressed callback
        // Description: Connects the medication-save icon disabled during saving or after completion to the captured operation `onPressed()`.
        // Parameters:
        // - None.
        // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
        onPressed: isDisabled ? null : () async => onPressed(),
        icon: isMedicationSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  color: MedBuddyColors.primary,
                ),
              )
            : Icon(
                isMedicationSaved
                    ? Icons.check_circle_outline
                    : Icons.save_outlined,
                size: 22,
              ),
      ),
    );
  }
}

// 클래스명: _DoseInfoRow
// 역할: 복용량·횟수·기간의 라벨과 값을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 복용량·횟수·기간의 라벨과 값 위젯을 구성한다.
// 속성:
// - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
class _DoseInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final UserSetting userSetting;

  // 함수이름: _DoseInfoRow
  // 함수역할: 복용량·횟수·기간의 라벨과 값에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - icon (IconData): 기본 또는 선택 상태에서 표시할 아이콘.
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // 반환값: 입력 설정이 반영된 _DoseInfoRow 인스턴스.
  const _DoseInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.userSetting,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 복용량·횟수·기간의 라벨과 값 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 복용량·횟수·기간의 라벨과 값에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Row(
      children: [
        Icon(icon, color: MedBuddyColors.primary, size: 21),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 15 * scale,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
        Flexible(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: MedBuddyColors.mint,
              borderRadius: MedBuddyRadii.pill,
            ),
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MedBuddyColors.primaryDark,
                fontSize: 15 * scale,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// 클래스명: _ResultText
// 역할: 처방 분석 결과 확인과 개별·전체 복약 일정 저장에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 처방 분석 결과 확인과 개별·전체 복약 일정 저장에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _ResultText {
  final String language;

  // 함수이름: _ResultText
  // 함수역할: 처방 분석 결과 확인과 개별·전체 복약 일정 저장에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _ResultText 인스턴스.
  const _ResultText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드가 en과 정확히 일치하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language == 'en';

  // 함수이름: title
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전 분석 결과" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get title => isEnglish ? 'Prescription Analysis Result' : '처방전 분석 결과';
  // 함수이름: back
  // 함수역할: 현재 언어와 입력값에 맞춰 "뒤로가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get back => isEnglish ? 'Back' : '뒤로가기';
  // 함수이름: complete
  // 함수역할: 현재 언어와 입력값에 맞춰 "분석 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get complete => isEnglish ? 'Analysis Complete' : '분석 완료';
  // 함수이름: summary
  // 함수역할: 현재 언어와 입력값에 맞춰 "$count개의 복약 일정을 저장할 수 있습니다" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String summary(int count) => isEnglish
      ? '$count medication item${count == 1 ? '' : 's'} ready to save'
      : '$count개의 복약 일정을 저장할 수 있습니다';
  // 함수이름: dose
  // 함수역할: 현재 언어와 입력값에 맞춰 "1회 투약량" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get dose => isEnglish ? 'Dose' : '1회 투약량';
  // 함수이름: frequency
  // 함수역할: 현재 언어와 입력값에 맞춰 "1일 횟수" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get frequency => isEnglish ? 'Frequency' : '1일 횟수';
  // 함수이름: duration
  // 함수역할: 현재 언어와 입력값에 맞춰 "총 투약일" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get duration => isEnglish ? 'Duration' : '총 투약일';
  // 함수이름: noInformation
  // 함수역할: 현재 언어와 입력값에 맞춰 "정보 없음" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noInformation => isEnglish ? 'No information' : '정보 없음';
  // 함수이름: saveAll
  // 함수역할: 현재 언어와 입력값에 맞춰 "전체 저장하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saveAll => isEnglish ? 'Save All' : '전체 저장하기';
  // 함수이름: savingAll
  // 함수역할: 현재 언어와 입력값에 맞춰 "전체 저장 중..." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get savingAll => isEnglish ? 'Saving all...' : '전체 저장 중...';
  // 함수이름: allSaved
  // 함수역할: 현재 언어와 입력값에 맞춰 "전체 저장 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get allSaved => isEnglish ? 'All Saved' : '전체 저장 완료';
  // 함수이름: saveSchedule
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 일정 저장하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saveSchedule =>
      isEnglish ? 'Save Medication Schedule' : '복약 일정 저장하기';
  // 함수이름: saved
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saved => isEnglish ? 'Saved' : '저장 완료';
  // 함수이름: saving
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장 중..." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saving => isEnglish ? 'Saving...' : '저장 중...';
  // 함수이름: saveCompletedTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 일정 저장 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saveCompletedTitle =>
      isEnglish ? 'Medication schedule saved' : '복약 일정 저장 완료';
  // 함수이름: saveCompletedDescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장한 약을 오늘 일정이나 저장 목록에서 바로 확인할 수 있습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get saveCompletedDescription => isEnglish
      ? 'Review the saved schedule now or return home.'
      : '저장한 약을 오늘 일정이나 저장 목록에서 바로 확인할 수 있습니다.';
  // 함수이름: openTodaySchedule
  // 함수역할: 현재 언어와 입력값에 맞춰 "오늘 일정 확인" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get openTodaySchedule =>
      isEnglish ? 'View today\'s schedule' : '오늘 일정 확인';
  // 함수이름: openSavedMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장된 정보 보기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get openSavedMedication =>
      isEnglish ? 'View saved medication' : '저장된 정보 보기';
  // 함수이름: returnHome
  // 함수역할: 현재 언어와 입력값에 맞춰 "홈으로 돌아가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get returnHome => isEnglish ? 'Return home' : '홈으로 돌아가기';
}
