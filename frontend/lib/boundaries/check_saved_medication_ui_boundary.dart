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
import '../widgets/medbuddy_page_header.dart';

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

// 클래스명: _CheckSavedMedicationUIState
// 역할: 저장 목록의 필터·정렬·선택과 등록 흐름을 연결한다.
// 주요 책임: 현재 조회 조건의 유효 ID만 삭제하고 실패한 선택을 유지한다.
// 속성: _selectedMedicationIds는 선택 ID, _isDeleting은 중복 조작 방지 상태이다.
class _CheckSavedMedicationUIState extends State<CheckSavedMedicationUI> {
  final Set<int> _selectedMedicationIds = {};
  bool _isSelectionMode = false;
  bool _isDeleting = false;
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

  // 함수이름: _buildScreen
  // 함수역할: 일정 화면과 같은 헤더 아래 조회 도구·본문을 스크롤하고 선택 삭제 버튼은 하단에 고정한다.
  // 매개변수: context는 화면 위치, viewModel은 조회 상태. 반환값: 뒤로가기를 제어하는 화면.
  Widget _buildScreen(BuildContext context, MedBuddyViewModel viewModel) {
    final text = _SavedMedicationText(viewModel.userSetting.language);
    final medications = viewModel.savedMedicationInfoList;
    final titleActions = [
      _buildSortMenu(text),
      IconButton(
        key: const Key('saved-medication-select'),
        tooltip: text.selectionTitle,
        onPressed: _isDeleting || _visibleMedicationIds(viewModel).isEmpty
            ? null
            : _startSelection,
        icon: const Icon(Icons.checklist),
      ),
    ];
    final visibleIds = _visibleMedicationIds(viewModel);
    final selectedIds = _selectedMedicationIds.intersection(visibleIds);

    return PopScope(
      canPop: !_isSelectionMode && !_isDeleting,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        backgroundColor: MedBuddyColors.pageBackground,
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: MedBuddySpacing.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MedBuddyPageHeader(
                    title: _isSelectionMode ? text.selectionTitle : text.title,
                    subtitle: _isSelectionMode ? null : text.subtitle,
                    prominent: !widget.showCloseButton && !_isSelectionMode,
                    backButtonKey: const ValueKey('savedMedicationCloseButton'),
                    leading: _isSelectionMode
                        ? IconButton(
                            key: const Key('saved-medication-cancel-selection'),
                            tooltip: text.cancelSelection,
                            onPressed: _isDeleting ? null : _endSelection,
                            icon: const Icon(Icons.close),
                          )
                        : null,
                    onBackRequested:
                        widget.showCloseButton &&
                            !_isSelectionMode &&
                            !_isDeleting
                        ? _requestBack
                        : null,
                    actions: [
                      if (!_isSelectionMode && medications.isNotEmpty)
                        ...titleActions,
                    ],
                  ),
                  Expanded(
                    child: CustomScrollView(
                      key: const Key('saved-medication-scroll'),
                      slivers: [
                        const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (medications.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _SavedMedicationFilterControl(
                                          filterMode: _filterMode,
                                          text: text,
                                          enabled: !_isDeleting,
                                          onChanged: _changeFilter,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _SavedMedicationSortControl(
                                        sortDirection: _sortDirection,
                                        text: text,
                                        enabled: !_isDeleting,
                                        onDirectionChanged:
                                            _changeSortDirection,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (_isSelectionMode)
                                  _SavedMedicationSelectionControl(
                                    text: text,
                                    selectedCount: selectedIds.length,
                                    visibleCount: visibleIds.length,
                                    enabled: !_isDeleting,
                                    onToggleAll: _toggleAll,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          sliver: _buildContent(viewModel, medications, text),
                        ),
                      ],
                    ),
                  ),
                  if (_isSelectionMode)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: _SelectionDeleteBar(
                        text: text,
                        userSetting: viewModel.userSetting,
                        selectedCount: selectedIds.length,
                        isDeleting: _isDeleting,
                        // 함수역할: 보이는 선택 약의 삭제를 확인한다.
                        // 매개변수: 없음. 반환값: 삭제 확인·처리 완료.
                        onDeleteRequested: () =>
                            _confirmAndDeleteSelectedMedications(
                              viewModel: viewModel,
                              text: text,
                            ),
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

  // 함수이름: _buildSortMenu
  // 함수역할: 제목의 정렬 기준 메뉴를 만든다. 매개변수: text는 번역 문구. 반환값: 정렬 메뉴.
  Widget _buildSortMenu(_SavedMedicationText text) {
    return PopupMenuButton<_SavedMedicationSortMode>(
      key: const ValueKey('savedMedicationSortModeButton'),
      tooltip: text.sortSettings,
      initialValue: _sortMode,
      enabled: !_isDeleting,
      onSelected: _changeSortMode,
      // 함수역할: 등록일·복용일 선택지를 구성한다. 매개변수: context. 반환값: 메뉴 항목.
      itemBuilder: (context) => [
        for (final mode in _SavedMedicationSortMode.values)
          PopupMenuItem(
            value: mode,
            child: _SavedMedicationSortMenuItem(
              label: mode == _SavedMedicationSortMode.registeredDate
                  ? text.sortByRegisteredDate
                  : text.sortByMedicationDate,
              isSelected: _sortMode == mode,
            ),
          ),
      ],
      icon: const Icon(Icons.tune_rounded),
    );
  }

  // 함수이름: _startSelection
  // 함수역할: 빈 선택으로 삭제 모드를 연다. 매개변수: 없음. 반환값: 없음.
  void _startSelection() {
    if (_isDeleting) return;
    setState(() {
      _isSelectionMode = true;
      _selectedMedicationIds.clear();
    });
  }

  // 함수이름: _endSelection
  // 함수역할: 삭제하지 않고 선택을 취소한다. 매개변수: 없음. 반환값: 없음.
  void _endSelection() {
    if (_isDeleting) return;
    setState(() {
      _isSelectionMode = false;
      _selectedMedicationIds.clear();
    });
  }

  // 함수이름: _handleBack
  // 함수역할: 시스템 뒤로가기는 화면보다 선택을 먼저 닫는다.
  // 매개변수: didPop은 이동 여부, result는 이동 결과. 반환값: 없음.
  void _handleBack(bool didPop, Object? result) {
    if (!didPop && _isSelectionMode && !_isDeleting) _endSelection();
  }

  // 함수이름: _requestBack
  // 함수역할: 하위 화면의 이전 화면으로 돌아간다. 매개변수: 없음. 반환값: 없음.
  void _requestBack() {
    if (!_isDeleting) Navigator.maybePop(context);
  }

  // 함수이름: _changeFilter
  // 함수역할: 실제 조건 변경 시 숨겨지는 선택을 모두 비운다.
  // 매개변수: mode는 새 조회 조건. 반환값: 없음.
  void _changeFilter(_SavedMedicationFilterMode mode) {
    if (_isDeleting || mode == _filterMode) return;
    setState(() {
      _filterMode = mode;
      _selectedMedicationIds.clear();
    });
  }

  // 함수이름: _showAll
  // 함수역할: 빈 결과에서 전체 목록으로 전환한다. 매개변수: 없음. 반환값: 없음.
  void _showAll() => _changeFilter(_SavedMedicationFilterMode.all);

  // 함수이름: _changeSortMode
  // 함수역할: 제목 메뉴의 날짜 기준을 적용한다. 매개변수: mode는 정렬 기준. 반환값: 없음.
  void _changeSortMode(_SavedMedicationSortMode mode) {
    if (_isDeleting) return;
    setState(() => _sortMode = mode);
  }

  // 함수이름: _changeSortDirection
  // 함수역할: 날짜 표시 순서를 바꾼다. 매개변수: direction은 정렬 방향. 반환값: 없음.
  void _changeSortDirection(_SavedMedicationSortDirection direction) {
    if (_isDeleting) return;
    setState(() => _sortDirection = direction);
  }

  // 함수이름: _visibleMedicationIds
  // 함수역할: 현재 필터에 보이는 양수 ID를 중복 없이 구한다.
  // 매개변수: viewModel은 최신 목록. 반환값: 삭제 가능한 ID 집합.
  Set<int> _visibleMedicationIds(MedBuddyViewModel viewModel) =>
      _filterMedicationList(viewModel.savedMedicationInfoList)
          // 함수역할: 약의 저장 ID를 읽는다. 매개변수: medication. 반환값: 선택적 ID.
          .map((medication) => medication.id)
          .whereType<int>()
          // 함수역할: 유효한 저장 ID만 허용한다. 매개변수: id. 반환값: 양수 여부.
          .where((id) => id > 0)
          .toSet();

  // 함수이름: _toggleAll
  // 함수역할: 현재 보이는 유효 약만 전체 선택하거나 해제한다. 매개변수: 없음. 반환값: 없음.
  void _toggleAll() {
    if (_isDeleting) return;
    final ids = _visibleMedicationIds(context.read<MedBuddyViewModel>());
    final allSelected =
        ids.isNotEmpty &&
        _selectedMedicationIds.intersection(ids).length == ids.length;
    setState(() {
      _selectedMedicationIds.clear();
      if (!allSelected) _selectedMedicationIds.addAll(ids);
    });
  }

  // 함수이름: _changeSelection
  // 함수역할: 보이는 유효 약 한 개의 선택만 변경한다.
  // 매개변수: medication은 대상 약, selected는 선택 여부. 반환값: 없음.
  void _changeSelection(MedicationDetail medication, bool selected) {
    if (_isDeleting) return;
    final ids = _visibleMedicationIds(context.read<MedBuddyViewModel>());
    final id = medication.id;
    if (id == null || !ids.contains(id)) return;
    setState(() {
      _selectedMedicationIds.retainAll(ids);
      if (selected) {
        _selectedMedicationIds.add(id);
      } else {
        _selectedMedicationIds.remove(id);
      }
    });
  }

  // 함수이름: _buildContent
  // 함수역할: 로딩·빈 결과·날짜별 목록을 나누고 기존 등록 및 상세 흐름을 연결한다.
  // 매개변수: viewModel은 상태, savedMedicationInfoList는 전체 목록, text는 문구.
  // 반환값: 스크롤 가능한 목록 또는 빈 상태.
  Widget _buildContent(
    MedBuddyViewModel viewModel,
    List<MedicationDetail> savedMedicationInfoList,
    _SavedMedicationText text,
  ) {
    if (viewModel.isSavedMedicationLoading && savedMedicationInfoList.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: CircularProgressIndicator(color: MedBuddyColors.primary),
        ),
      );
    }
    if (savedMedicationInfoList.isEmpty) {
      return _SavedMedicationEmptyState(
        text: text,
        userSetting: viewModel.userSetting,
        onPrescriptionInputRequested: _isDeleting
            ? null
            // 함수역할: 기존 등록 선택을 연다. 매개변수: 없음. 반환값: 선택 처리 완료.
            : () => _showMedicationCaptureOptions(viewModel: viewModel),
      );
    }
    final filtered = _filterMedicationList(savedMedicationInfoList);
    if (filtered.isEmpty) {
      return _SavedMedicationFilteredEmptyState(
        filterMode: _filterMode,
        text: text,
        onShowAll: _isDeleting ? null : _showAll,
        onRegister: _isDeleting
            ? null
            // 함수역할: 기존 약 등록·식별을 연다. 매개변수: 없음. 반환값: 선택 처리 완료.
            : () => _showMedicationCaptureOptions(viewModel: viewModel),
      );
    }
    final groups = _SavedMedicationGroup.fromMedicationList(
      filtered,
      sortMode: _sortMode,
      sortDirection: _sortDirection,
    );
    return SliverList.builder(
      itemCount: groups.length,
      // 함수역할: 날짜 묶음에 선택·상세·삭제 동작을 연결한다.
      // 매개변수: context는 화면 위치, index는 묶음 순번. 반환값: 날짜별 목록.
      itemBuilder: (context, index) => _SavedMedicationDateCard(
        group: groups[index],
        text: text,
        userSetting: viewModel.userSetting,
        isSelectionMode: _isSelectionMode,
        enabled: !_isDeleting,
        selectedMedicationIds: _selectedMedicationIds,
        onSelectionChanged: _changeSelection,
        // 함수역할: 약 상세를 연다. 매개변수: medication은 대상 약. 반환값: 없음.
        onGuideRequested: (medication) => _showMedicationDetail(
          medication: medication,
          text: text,
          userSetting: viewModel.userSetting,
        ),
        // 함수역할: 약 사진을 연다. 매개변수: medication은 대상 약. 반환값: 없음.
        onImageRequested: (medication) => _showMedicationImage(
          medication: medication,
          text: text,
          userSetting: viewModel.userSetting,
        ),
        // 함수역할: 날짜 묶음 삭제를 확인한다. 매개변수: 없음. 반환값: 삭제 처리 완료.
        onDeleteRequested: () => _confirmAndDeleteMedicationGroup(
          viewModel: viewModel,
          group: groups[index],
          text: text,
        ),
      ),
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
  // 함수역할: 날짜 묶음 중 현재 보이는 약의 삭제를 확인한다.
  // 매개변수: viewModel은 삭제 흐름, group은 묶음, text는 문구. 반환값: 처리 완료.
  Future<void> _confirmAndDeleteMedicationGroup({
    required MedBuddyViewModel viewModel,
    required _SavedMedicationGroup group,
    required _SavedMedicationText text,
  }) => _confirmAndDeleteMedications(
    viewModel: viewModel,
    text: text,
    candidateIds: group.medications
        // 함수역할: 묶음의 저장 ID를 읽는다. 매개변수: medication. 반환값: 선택적 ID.
        .map((medication) => medication.id)
        .whereType<int>()
        .toSet(),
  );

  // 함수이름: _confirmAndDeleteSelectedMedications
  // 함수역할: 선택 집합의 복사본으로 삭제를 확인한다.
  // 매개변수: viewModel은 삭제 흐름, text는 문구. 반환값: 처리 완료.
  Future<void> _confirmAndDeleteSelectedMedications({
    required MedBuddyViewModel viewModel,
    required _SavedMedicationText text,
  }) => _confirmAndDeleteMedications(
    viewModel: viewModel,
    text: text,
    candidateIds: Set<int>.from(_selectedMedicationIds),
  );

  // 함수이름: _confirmAndDeleteMedications
  // 함수역할: 보이는 유효 ID만 재검증해 삭제하고 남은 실패 항목은 선택을 유지한다.
  // 매개변수: viewModel은 기존 일괄 삭제 흐름, text는 문구, candidateIds는 확인 대상.
  // 반환값: 확인 취소 또는 삭제 완료. 실패 예외에도 조작 잠금은 해제한다.
  Future<void> _confirmAndDeleteMedications({
    required MedBuddyViewModel viewModel,
    required _SavedMedicationText text,
    required Set<int> candidateIds,
  }) async {
    if (_isDeleting) return;
    final ids = candidateIds.intersection(_visibleMedicationIds(viewModel));
    if (ids.isEmpty) return;
    setState(() => _isDeleting = true);
    try {
      final shouldDelete = await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withAlpha(115),
        // 함수역할: 기존 삭제 확인을 표시한다. 매개변수: context. 반환값: 확인 창.
        builder: (context) => _DeleteConfirmationDialog(text: text),
      );
      if (!mounted || shouldDelete != true) return;
      // 확인 중 조회 결과가 바뀌어도 숨겨진 약을 삭제하지 않는다.
      ids.retainAll(_visibleMedicationIds(viewModel));
      if (ids.isEmpty) return;
      final result = await viewModel.requestDeleteSavedMedications(ids);
      if (!mounted) return;
      setState(() {
        _selectedMedicationIds.retainAll(_visibleMedicationIds(viewModel));
        _isSelectionMode = _selectedMedicationIds.isNotEmpty;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.deleteResult(result))));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
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
