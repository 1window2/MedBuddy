// 파일명: check_saved_medication_ui_boundary.dart
// 역할: 저장된 복약 정보 조회, 필터·정렬 및 선택 삭제를 제공한다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'check_medication_detail_ui_boundary.dart';
import 'guided_prescription_camera_ui_boundary.dart';
import 'manual_medication_entry_ui_boundary.dart';
import 'medication_capture_options_ui_boundary.dart';
import 'pill_identification_ui_boundary.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_image_url_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_view_model.dart';
import '../viewmodels/medbuddy_feature_updates.dart';

part 'check_saved_medication_empty_widgets.dart';
part 'check_saved_medication_filter_widgets.dart';
part 'check_saved_medication_list_widgets.dart';
part 'check_saved_medication_support.dart';

// 파일명: check_saved_medication_ui_boundary.dart
// 역할: 사용자가 저장한 복약 정보를 날짜별 목록으로 보여주는 화면을 구성한다.

// Class Name: CheckSavedMedicationUI
// Role: Represents date-grouped saved medications, filtering, and selection deletion.
// Responsibilities:
// - Loads saved medication on entry.
// - Groups medication rows by saved date.
// - Provides guidance, photo, and deletion dialogs.
// Attributes:
// - showCloseButton (bool): Whether to show the navigation action leaving the screen.
class CheckSavedMedicationUI extends StatefulWidget {
  final bool showCloseButton;

  // Function Name: CheckSavedMedicationUI
  // Description: Initializes date-grouped saved medications, filtering, and selection deletion with the supplied configuration.
  // Parameters:
  // - key (Key?): Widget identity used to distinguish elements and preserve state.
  // - showCloseButton (bool): Whether to show the navigation action leaving the screen.
  // Returns: Initialized CheckSavedMedicationUI instance.
  const CheckSavedMedicationUI({super.key, this.showCloseButton = true});

  // Function Name: createState
  // Description: Creates the state object that coordinates date-grouped saved medications, filtering, and selection deletion.
  // Parameters:
  // - None.
  // Returns: A new _CheckSavedMedicationUIState instance.
  @override
  State<CheckSavedMedicationUI> createState() => _CheckSavedMedicationUIState();
}

// 클래스명: _SavedMedicationSortMode
// 역할: 약품 목록의 날짜 정렬 기준을 담당한다.
// 주요 책임:
// - 약품 목록의 날짜 정렬 기준에서 지원하는 선택지를 열거하고 구분한다: registeredDate, medicationDate.
enum _SavedMedicationSortMode { registeredDate, medicationDate }

// 클래스명: _SavedMedicationSortDirection
// 역할: 날짜 정렬의 오름차순·내림차순을 담당한다.
// 주요 책임:
// - 날짜 정렬의 오름차순·내림차순에서 지원하는 선택지를 열거하고 구분한다: ascending, descending.
enum _SavedMedicationSortDirection { ascending, descending }

// 클래스명: _SavedMedicationFilterMode
// 역할: 복용 중·복용 종료·전체 표시 범위를 담당한다.
// 주요 책임:
// - 복용 중·복용 종료·전체 표시 범위에서 지원하는 선택지를 열거하고 구분한다: active, ended, all.
enum _SavedMedicationFilterMode { active, ended, all }

// Class Name: _CheckSavedMedicationUIState
// Role: Manages state for date-grouped saved medications, filtering, and selection deletion.
// Responsibilities:
// - Lays out the saved-medication heading, ordering, filters, and selection controls for the viewport width.
// - Routes task and image-source choices into pill identification, manual entry, or prescription OCR.
// - Confirms and deletes selected medications, retaining selection only for IDs that remain afterward.
// Attributes:
// - _selectedMedicationIds (Set<int>): Medication IDs selected for attachment or deletion.
// - _isSelectionMode (bool): Whether attachment or deletion selection replaces normal interaction.
// - _sortMode (_SavedMedicationSortMode): Registration-date or prescription-date sort field.
// - _sortDirection (_SavedMedicationSortDirection): Ascending or descending date-sort direction.
class _CheckSavedMedicationUIState extends State<CheckSavedMedicationUI> {
  final Set<int> _selectedMedicationIds = {};
  bool _isSelectionMode = false;
  _SavedMedicationSortMode _sortMode = _SavedMedicationSortMode.registeredDate;
  _SavedMedicationSortDirection _sortDirection =
      _SavedMedicationSortDirection.descending;
  _SavedMedicationFilterMode _filterMode = _SavedMedicationFilterMode.active;

  // Function Name: initState
  // Description: Requests saved medications from the view model after the first frame.
  // Parameters:
  // - None.
  // Returns: None; updates state or performs the documented action.
  @override
  void initState() {
    super.initState();
    // Function Name: initState.addPostFrameCallback callback
    // Description: Connects date-grouped saved medications, filtering, and selection deletion to the captured operation `context.read<MedBuddyViewModel>(); viewModel.fetchSavedMedicationInfo()`.
    // Parameters:
    // - _ (inferred by callback contract): Argument required by the callback contract but unused by the body.
    // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final viewModel = context.read<MedBuddyViewModel>();
      await viewModel.fetchSavedMedicationInfo();
    });
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 저장 약품의 날짜별 조회·필터·선택 삭제 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 저장 약품의 날짜별 조회·필터·선택 삭제에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<MedBuddyViewModel>();
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewModel.updatesFor(MedBuddyFeature.savedMedication),
        viewModel.updatesFor(MedBuddyFeature.userSetting),
      ]),
      // 함수이름: build.builder callback
      // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context, _) => _buildScreen(context, viewModel),
    );
  }

  // Function Name: _buildScreen
  // Description: Lays out the saved-medication heading, ordering, filters, and selection controls for the viewport width.
  // Parameters:
  // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // Returns: Widget tree for date-grouped saved medications, filtering, and selection deletion.
  Widget _buildScreen(BuildContext context, MedBuddyViewModel viewModel) {
    final userSetting = viewModel.userSetting;
    final text = _SavedMedicationText(userSetting.language);
    final savedMedicationInfoList = viewModel.savedMedicationInfoList;
    final compactLayout =
        MediaQuery.sizeOf(context).height < 700 ||
        MediaQuery.textScalerOf(context).scale(16) > 19;

    return Scaffold(
      backgroundColor: MedBuddyColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: MedBuddySpacing.contentMaxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                MedBuddySpacing.pageHorizontal,
                compactLayout ? 14 : 24,
                MedBuddySpacing.pageHorizontal,
                compactLayout ? 16 : 28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (widget.showCloseButton)
                        IconButton(
                          key: const ValueKey('savedMedicationCloseButton'),
                          tooltip: text.close,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 42,
                            height: 42,
                          ),
                          // 함수이름: _buildScreen.onPressed callback
                          // 함수역할: `Navigator.pop(context)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close,
                            color: MedBuddyColors.textMuted,
                            size: 30,
                          ),
                        ),
                      if (!widget.showCloseButton) const Spacer(),
                      if (savedMedicationInfoList.isNotEmpty)
                        PopupMenuButton<_SavedMedicationSortMode>(
                          key: const ValueKey('savedMedicationSortModeButton'),
                          tooltip: text.sortSettings,
                          initialValue: _sortMode,
                          // 함수이름: _buildScreen.onSelected callback
                          // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에서 캡처된 작업 `setState(() {_sortMode = sortMode;})`을 실행한다.
                          // 매개변수:
                          // - sortMode (콜백 계약에서 추론): 약품 등록일 또는 처방일 정렬 기준.
                          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                          onSelected: (sortMode) {
                            // 함수이름: _buildScreen.setState callback
                            // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제의 입력·요청 상태를 `_sortMode = sortMode`로 갱신한다.
                            // 매개변수:
                            // - 없음.
                            // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                            setState(() {
                              _sortMode = sortMode;
                            });
                          },
                          // 함수이름: _buildScreen.itemBuilder callback
                          // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
                          // 매개변수:
                          // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
                          // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: _SavedMedicationSortMode.registeredDate,
                              child: _SavedMedicationSortMenuItem(
                                label: text.sortByRegisteredDate,
                                isSelected:
                                    _sortMode ==
                                    _SavedMedicationSortMode.registeredDate,
                              ),
                            ),
                            PopupMenuItem(
                              value: _SavedMedicationSortMode.medicationDate,
                              child: _SavedMedicationSortMenuItem(
                                label: text.sortByMedicationDate,
                                isSelected:
                                    _sortMode ==
                                    _SavedMedicationSortMode.medicationDate,
                              ),
                            ),
                          ],
                          icon: const Icon(Icons.tune_rounded),
                        ),
                    ],
                  ),
                  SizedBox(height: compactLayout ? 14 : 30),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          text.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0A0A0A),
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      if (savedMedicationInfoList.isNotEmpty)
                        TextButton(
                          // 함수이름: _buildScreen.onPressed callback
                          // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에서 캡처된 작업 `setState(() {_isSelectionMode = !_isSelectionMode; _selectedMedicationIds.clear();})`을 실행한다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                          onPressed: () {
                            // 함수이름: _buildScreen.setState callback
                            // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제의 입력·요청 상태를 `_isSelectionMode = !_isSelectionMode`로 갱신한다.
                            // 매개변수:
                            // - 없음.
                            // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                            setState(() {
                              _isSelectionMode = !_isSelectionMode;
                              _selectedMedicationIds.clear();
                            });
                          },
                          child: Text(
                            _isSelectionMode ? text.done : text.select,
                          ),
                        ),
                    ],
                  ),
                  if (savedMedicationInfoList.isNotEmpty) ...[
                    SizedBox(height: compactLayout ? 8 : 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _SavedMedicationFilterControl(
                            filterMode: _filterMode,
                            text: text,
                            // 함수이름: _buildScreen.onChanged callback
                            // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에서 캡처된 작업 `setState(() {_filterMode = filterMode; _selectedMedicationIds.clear();})`을 실행한다.
                            // 매개변수:
                            // - filterMode (콜백 계약에서 추론): 저장 약품의 복용 중·종료·전체 표시 기준.
                            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                            onChanged: (filterMode) {
                              // 함수이름: _buildScreen.setState callback
                              // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제의 입력·요청 상태를 `_filterMode = filterMode`로 갱신한다.
                              // 매개변수:
                              // - 없음.
                              // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                              setState(() {
                                _filterMode = filterMode;
                                _selectedMedicationIds.clear();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        _SavedMedicationSortControl(
                          sortDirection: _sortDirection,
                          text: text,
                          // 함수이름: _buildScreen.onDirectionChanged callback
                          // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에서 캡처된 작업 `setState(() {_sortDirection = sortDirection;})`을 실행한다.
                          // 매개변수:
                          // - sortDirection (콜백 계약에서 추론): 날짜 정렬의 오름차순·내림차순 선택.
                          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                          onDirectionChanged: (sortDirection) {
                            // 함수이름: _buildScreen.setState callback
                            // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제의 입력·요청 상태를 `_sortDirection = sortDirection`로 갱신한다.
                            // 매개변수:
                            // - 없음.
                            // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                            setState(() {
                              _sortDirection = sortDirection;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: compactLayout ? 10 : 20),
                  Expanded(
                    child: _buildContent(
                      viewModel,
                      savedMedicationInfoList,
                      text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 함수이름: _buildContent
  // 함수역할: 저장 목록 로딩, 빈 상태, 날짜별 목록 상태를 분기해 화면 본문을 만든다.
  // 매개변수:
  // - viewModel (MedBuddyViewModel): 화면 상태·사용자 설정·복약 작업을 제공하는 ViewModel.
  // - savedMedicationInfoList (List<MedicationDetail>): 조회·선택·정렬·표시에 사용할 약품 목록.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 저장 약품의 날짜별 조회·필터·선택 삭제에 쓰는 위젯 트리.
  Widget _buildContent(
    MedBuddyViewModel viewModel,
    List<MedicationDetail> savedMedicationInfoList,
    _SavedMedicationText text,
  ) {
    if (viewModel.isSavedMedicationLoading && savedMedicationInfoList.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: MedBuddyColors.primary),
      );
    }

    if (savedMedicationInfoList.isEmpty) {
      return _SavedMedicationEmptyState(
        text: text,
        userSetting: viewModel.userSetting,
        // 함수이름: _buildContent.onPrescriptionInputRequested callback
        // 함수역할: 입력 작업과 사진 출처 선택을 처리해 알약 식별·직접 입력·처방전 OCR 흐름으로 연결한다.
        // 매개변수:
        // - 없음.
        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
        onPrescriptionInputRequested: () async {
          await _showMedicationCaptureOptions(viewModel: viewModel);
        },
      );
    }

    final filteredMedicationInfoList = _filterMedicationList(
      savedMedicationInfoList,
    );
    if (filteredMedicationInfoList.isEmpty) {
      return _SavedMedicationFilteredEmptyState(
        filterMode: _filterMode,
        text: text,
      );
    }

    final groups = _SavedMedicationGroup.fromMedicationList(
      filteredMedicationInfoList,
      sortMode: _sortMode,
      sortDirection: _sortDirection,
    );

    final medicationListView = ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: groups.length,
      // Function Name: _buildContent.itemBuilder callback
      // Description: Composes date-grouped saved medications, filtering, and selection deletion with the current parent constraints for the active layout.
      // Parameters:
      // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
      // - index (int): Zero-based position of the target medication, photo, or row.
      // Returns: Widget subtree for the described layout or fallback.
      itemBuilder: (context, index) {
        return _SavedMedicationDateCard(
          group: groups[index],
          text: text,
          userSetting: viewModel.userSetting,
          isSelectionMode: _isSelectionMode,
          selectedMedicationIds: _selectedMedicationIds,
          // 함수이름: _buildContent.onSelectionChanged callback
          // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에서 캡처된 작업 `setState(() {if (selected) {_selectedMedicationIds.add(id);} else {_selectedMedicationIds.remove(id);}})`을 실행한다.
          // 매개변수:
          // - medication (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
          // - selected (콜백 계약에서 추론): 현재 선택 집합에 포함되는지 여부.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onSelectionChanged: (medication, selected) {
            final id = medication.id;
            if (id == null) {
              return;
            }
            // 함수이름: _buildContent.setState callback
            // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에서 캡처된 작업 `_selectedMedicationIds.add(id); _selectedMedicationIds.remove(id)`을 실행한다.
            // 매개변수:
            // - 없음.
            // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
            setState(() {
              if (selected) {
                _selectedMedicationIds.add(id);
              } else {
                _selectedMedicationIds.remove(id);
              }
            });
          },
          // Function Name: _buildContent.onGuideRequested callback
          // Description: Opens medication details using the saved detail data and user settings.
          // Parameters:
          // - medication (inferred by callback contract): Medication data to display, transform, save, or compare.
          // Returns: Completion of the captured interaction; any route result or state change is handled by that operation.
          onGuideRequested: (medication) {
            _showMedicationDetail(
              medication: medication,
              text: text,
              userSetting: viewModel.userSetting,
            );
          },
          // 함수이름: _buildContent.onImageRequested callback
          // 함수역할: 안전한 이미지 URL이 있는지 확인하고 약 사진 창 또는 사진 없음 안내를 표시한다.
          // 매개변수:
          // - medication (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onImageRequested: (medication) {
            _showMedicationImage(
              medication: medication,
              text: text,
              userSetting: viewModel.userSetting,
            );
          },
          // 함수이름: _buildContent.onDeleteRequested callback
          // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에서 캡처된 작업 `_confirmAndDeleteMedicationGroup(viewModel: viewModel, group: groups[index], text: text)`을 실행한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onDeleteRequested: () async {
            await _confirmAndDeleteMedicationGroup(
              viewModel: viewModel,
              group: groups[index],
              text: text,
            );
          },
        );
      },
    );

    if (!_isSelectionMode) {
      return medicationListView;
    }

    return Column(
      children: [
        Expanded(child: medicationListView),
        _SelectionDeleteBar(
          text: text,
          userSetting: viewModel.userSetting,
          selectedCount: _selectedMedicationIds.length,
          // 함수이름: _buildContent.onDeleteRequested callback
          // 함수역할: 선택 약 삭제를 확인받아 일괄 삭제하고 실패해 남은 ID만 선택 상태에 유지한다.
          // 매개변수:
          // - 없음.
          // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
          onDeleteRequested: () async {
            await _confirmAndDeleteSelectedMedications(
              viewModel: viewModel,
              text: text,
            );
          },
        ),
      ],
    );
  }

  // 함수이름: _filterMedicationList
  // 함수역할: 복용 기간과 오늘 날짜를 비교해 사용자가 선택한 상태의 약만 반환한다.
  // 매개변수:
  // - medications (List<MedicationDetail>): 조회·선택·정렬·표시에 사용할 약품 목록.
  // 반환값: List<MedicationDetail>: 선택한 복용 상태에 해당하는 저장 약품 목록.
  List<MedicationDetail> _filterMedicationList(
    List<MedicationDetail> medications,
  ) {
    final today = DateTime.now();
    return medications
        // 함수이름: _filterMedicationList.where callback
        // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에 대해 `switch (_filterMode) {_SavedMedicationFilterMode.active => medication.isActiveOn(today), _SavedMedicationFilterMode.ended ...` 조건으로 컬렉션 항목을 판별한다.
        // 매개변수:
        // - medication (콜백 계약에서 추론): 표시·변환·저장·비교할 약품 데이터.
        // 반환값: 전달된 항목이 조건을 만족하는지 나타내는 bool.
        .where((medication) {
          return switch (_filterMode) {
            _SavedMedicationFilterMode.active => medication.isActiveOn(today),
            _SavedMedicationFilterMode.ended =>
              medication.medicationEndDate != null &&
                  medication.medicationEndDate!.isBefore(
                    DateTime(today.year, today.month, today.day),
                  ),
            _SavedMedicationFilterMode.all => true,
          };
        })
        .toList(growable: false);
  }

  // Function Name: _showMedicationCaptureOptions
  // Description: Routes task and image-source choices into pill identification, manual entry, or prescription OCR.
  // Parameters:
  // - viewModel (MedBuddyViewModel): View model exposing screen state, user settings, and medication actions.
  // Returns: Future<void> completing when the requested interaction or refresh finishes.
  Future<void> _showMedicationCaptureOptions({
    required MedBuddyViewModel viewModel,
  }) async {
    final task = await showMedicationCaptureTaskOptions(
      context: context,
      userSetting: viewModel.userSetting,
    );
    if (!mounted || task == null) {
      return;
    }
    if (task == MedicationCaptureTask.multiplePills ||
        task == MedicationCaptureTask.individualPills) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          // 함수이름: _showMedicationCaptureOptions.builder callback
          // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
          // 매개변수:
          // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
          // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
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
      return;
    }
    if (task == MedicationCaptureTask.manual) {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          // 함수이름: _showMedicationCaptureOptions.builder callback
          // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
          // 매개변수:
          // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
          // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
          builder: (context) => ManualMedicationEntryUI(
            userSetting: viewModel.userSetting,
            onSaveRequested: viewModel.saveManualMedication,
          ),
        ),
      );
      return;
    }

    final source = await showPrescriptionImageSourceOptions(
      context: context,
      userSetting: viewModel.userSetting,
    );
    if (!mounted || source == null) {
      return;
    }

    if (source == PrescriptionImageSource.camera) {
      final image = await Navigator.push<XFile>(
        context,
        MaterialPageRoute<XFile>(
          // 함수이름: _showMedicationCaptureOptions.builder callback
          // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
          // 매개변수:
          // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
          // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
          builder: (context) =>
              GuidedPrescriptionCameraUI(userSetting: viewModel.userSetting),
        ),
      );
      if (!mounted || image == null) {
        return;
      }
      if (widget.showCloseButton) {
        Navigator.pop(context);
      }
      await viewModel.requestCapturedPrescriptionImage(image);
      return;
    }
    if (widget.showCloseButton) {
      Navigator.pop(context);
    }
    viewModel.requestPrescriptionImageFromGallery();
  }

  // 함수이름: _confirmAndDeleteMedicationGroup
  // 함수역할: 삭제 확인 팝업을 띄운 뒤 사용자가 승인하면 날짜 그룹의 약들을 삭제한다. 날짜 그룹 전체를 ViewModel의 일괄 삭제 흐름으로 전달한다.
  // 매개변수:
  // - viewModel (MedBuddyViewModel): 화면 상태·사용자 설정·복약 작업을 제공하는 ViewModel.
  // - group (_SavedMedicationGroup): 같은 날짜의 저장 약품 묶음.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _confirmAndDeleteMedicationGroup({
    required MedBuddyViewModel viewModel,
    required _SavedMedicationGroup group,
    required _SavedMedicationText text,
  }) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withAlpha(115),
      // 함수이름: _confirmAndDeleteMedicationGroup.builder callback
      // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context) {
        return _DeleteConfirmationDialog(text: text);
      },
    );
    if (shouldDelete != true) {
      return;
    }

    final result = await viewModel.requestDeleteSavedMedications(
      // Function Name: _confirmAndDeleteMedicationGroup.map callback
      // Description: Computes the mapped value for date-grouped saved medications, filtering, and selection deletion with `medication.id`.
      // Parameters:
      // - medication (inferred by callback contract): Medication data to display, transform, save, or compare.
      // Returns: The mapped value passed back to the collection operation.
      group.medications.map((medication) => medication.id).whereType<int>(),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.deleteResult(result))));
  }

  // 함수이름: _confirmAndDeleteSelectedMedications
  // 함수역할: 선택 약 삭제를 확인받아 일괄 삭제하고 실패해 남은 ID만 선택 상태에 유지한다.
  // 매개변수:
  // - viewModel (MedBuddyViewModel): 화면 상태·사용자 설정·복약 작업을 제공하는 ViewModel.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _confirmAndDeleteSelectedMedications({
    required MedBuddyViewModel viewModel,
    required _SavedMedicationText text,
  }) async {
    if (_selectedMedicationIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.noSelection)));
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withAlpha(115),
      // 함수이름: _confirmAndDeleteSelectedMedications.builder callback
      // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context) {
        return _DeleteConfirmationDialog(text: text);
      },
    );
    if (shouldDelete != true) {
      return;
    }

    final selectedIds = List<int>.from(_selectedMedicationIds);
    final result = await viewModel.requestDeleteSavedMedications(selectedIds);
    if (!mounted) {
      return;
    }
    final remainingIds = viewModel.savedMedicationInfoList
        // Function Name: _confirmAndDeleteSelectedMedications.map callback
        // Description: Computes the mapped value for date-grouped saved medications, filtering, and selection deletion with `medication.id`.
        // Parameters:
        // - medication (inferred by callback contract): Medication data to display, transform, save, or compare.
        // Returns: The mapped value passed back to the collection operation.
        .map((medication) => medication.id)
        .whereType<int>()
        .toSet();
    // Function Name: _confirmAndDeleteSelectedMedications.setState callback
    // Description: Updates the local input or request state for date-grouped saved medications, filtering, and selection deletion: `_isSelectionMode = _selectedMedicationIds.isNotEmpty`.
    // Parameters:
    // - None.
    // Returns: No payload; applies the captured state changes.
    setState(() {
      _selectedMedicationIds.retainAll(remainingIds);
      _isSelectionMode = _selectedMedicationIds.isNotEmpty;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.deleteResult(result))));
  }

  // Function Name: _showMedicationDetail
  // Description: Opens medication details using the saved detail data and user settings.
  // Parameters:
  // - medication (MedicationDetail): Medication data to display, transform, save, or compare.
  // - text (_SavedMedicationText): Localized labels used by this section.
  // - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
  // Returns: None; updates state or performs the documented action.
  void _showMedicationDetail({
    required MedicationDetail medication,
    required _SavedMedicationText text,
    required UserSetting userSetting,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        // Function Name: _showMedicationDetail.builder callback
        // Description: Composes date-grouped saved medications, filtering, and selection deletion with the current parent constraints for the active layout.
        // Parameters:
        // - context (BuildContext): Widget-tree location for theme, accessibility, and navigation.
        // Returns: Widget subtree for the described layout or fallback.
        builder: (context) => CheckMedicationDetailUI(
          medicationDetail: medication,
          userSetting: userSetting,
        ),
      ),
    );
  }

  // Function Name: _showMedicationImage
  // Description: Checks for a safe image URL before opening the medication photo dialog or showing an unavailable notice.
  // Parameters:
  // - medication (MedicationDetail): Medication data to display, transform, save, or compare.
  // - text (_SavedMedicationText): Localized labels used by this section.
  // - userSetting (UserSetting): User settings for language, accessibility, medication reminders, and persistence.
  // Returns: None; updates state or performs the documented action.
  void _showMedicationImage({
    required MedicationDetail medication,
    required _SavedMedicationText text,
    required UserSetting userSetting,
  }) {
    if (safeMedicationImageUrl(medication.imageUrl).isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.noImage)));
      return;
    }

    showDialog<void>(
      context: context,
      // 함수이름: _showMedicationImage.builder callback
      // 함수역할: 저장 약품의 날짜별 조회·필터·선택 삭제에 현재 부모의 레이아웃 제약을 적용해 현재 배치를 구성한다.
      // 매개변수:
      // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
      // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
      builder: (context) {
        return _MedicationImageDialog(
          medication: medication,
          text: text,
          userSetting: userSetting,
        );
      },
    );
  }
}
