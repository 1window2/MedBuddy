// 파일명: check_saved_medication_ui_boundary.dart
// 역할: 저장된 복약정보의 조회, 정렬, 선택 삭제와 상세 이동 화면을 제공한다.

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

// 클래스명: CheckSavedMedicationUI
// 역할: 저장된 복약 정보 조회, 약품 가이드 확인, 약 사진 확인, 삭제를 처리하는 화면이다.
// 주요 책임:
// - 화면 진입 시 저장된 복약 정보를 불러온다.
// - 저장 날짜별로 약 목록을 묶어 표 형태에 가깝게 표시한다.
// - 가이드/사진/삭제 팝업 같은 저장 목록 세부 동작을 제공한다.
class CheckSavedMedicationUI extends StatefulWidget {
  const CheckSavedMedicationUI({super.key});

  @override
  State<CheckSavedMedicationUI> createState() => _CheckSavedMedicationUIState();
}

// 열거형명: _SavedMedicationSortMode
// 역할: 저장된 복약 정보 목록에 적용할 날짜 정렬 기준을 구분한다.
enum _SavedMedicationSortMode { registeredDate, medicationDate }

// 열거형명: _SavedMedicationSortDirection
// 역할: 선택한 날짜 정렬 기준의 오름차순과 내림차순을 구분한다.
enum _SavedMedicationSortDirection { ascending, descending }

// 열거형명: _SavedMedicationFilterMode
// 역할: 현재 복용 중인 약, 복용이 끝난 약, 전체 약의 표시 범위를 구분한다.
enum _SavedMedicationFilterMode { active, ended, all }

class _CheckSavedMedicationUIState extends State<CheckSavedMedicationUI> {
  final Set<int> _selectedMedicationIds = {};
  bool _isSelectionMode = false;
  _SavedMedicationSortMode _sortMode = _SavedMedicationSortMode.registeredDate;
  _SavedMedicationSortDirection _sortDirection =
      _SavedMedicationSortDirection.descending;
  _SavedMedicationFilterMode _filterMode = _SavedMedicationFilterMode.active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final viewModel = context.read<MedBuddyViewModel>();
      await viewModel.fetchSavedMedicationInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<MedBuddyViewModel>();
    return ListenableBuilder(
      listenable: Listenable.merge([
        viewModel.updatesFor(MedBuddyFeature.savedMedication),
        viewModel.updatesFor(MedBuddyFeature.userSetting),
      ]),
      builder: (context, _) => _buildScreen(context, viewModel),
    );
  }

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
                  IconButton(
                    key: const ValueKey('savedMedicationCloseButton'),
                    tooltip: text.close,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 42,
                      height: 42,
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: MedBuddyColors.textMuted,
                      size: 30,
                    ),
                  ),
                  if (savedMedicationInfoList.isNotEmpty)
                    PopupMenuButton<_SavedMedicationSortMode>(
                      key: const ValueKey('savedMedicationSortModeButton'),
                      tooltip: text.sortSettings,
                      initialValue: _sortMode,
                      onSelected: (sortMode) {
                        setState(() {
                          _sortMode = sortMode;
                        });
                      },
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
                      onPressed: () {
                        setState(() {
                          _isSelectionMode = !_isSelectionMode;
                          _selectedMedicationIds.clear();
                        });
                      },
                      child: Text(_isSelectionMode ? text.done : text.select),
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
                        onChanged: (filterMode) {
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
                      onDirectionChanged: (sortDirection) {
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
                child: _buildContent(viewModel, savedMedicationInfoList, text),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 함수명: _buildContent
  // 함수역할:
  // - 저장 목록 로딩, 빈 상태, 날짜별 목록 상태를 분기해 화면 본문을 만든다.
  // 매개변수:
  // - viewModel: 저장 목록과 로딩 상태를 제공하는 ViewModel
  // - savedMedicationInfoList: 현재 화면에 표시할 저장된 복약 정보 목록
  // - text: 현재 언어에 맞는 저장 목록 문구 묶음
  // 반환값:
  // - 저장 목록 본문 Widget
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
      itemBuilder: (context, index) {
        return _SavedMedicationDateCard(
          group: groups[index],
          text: text,
          userSetting: viewModel.userSetting,
          isSelectionMode: _isSelectionMode,
          selectedMedicationIds: _selectedMedicationIds,
          onSelectionChanged: (medication, selected) {
            final id = medication.id;
            if (id == null) {
              return;
            }
            setState(() {
              if (selected) {
                _selectedMedicationIds.add(id);
              } else {
                _selectedMedicationIds.remove(id);
              }
            });
          },
          onGuideRequested: (medication) {
            _showMedicationDetail(
              medication: medication,
              text: text,
              userSetting: viewModel.userSetting,
            );
          },
          onImageRequested: (medication) {
            _showMedicationImage(
              medication: medication,
              text: text,
              userSetting: viewModel.userSetting,
            );
          },
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

  // 함수명: _filterMedicationList
  // 역할:
  // - 복용 기간과 오늘 날짜를 비교해 사용자가 선택한 상태의 약만 반환한다.
  List<MedicationDetail> _filterMedicationList(
    List<MedicationDetail> medications,
  ) {
    final today = DateTime.now();
    return medications
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

  // 함수이름: _showMedicationCaptureOptions
  // 함수역할:
  // - 저장 목록이 비어 있을 때 처방전 분석, 낱알약 식별, 직접 등록 중 작업을 선택하게 한다.
  // - 처방전 분석은 이미지 출처를 추가로 선택하고 나머지는 전용 화면으로 이동한다.
  // 매개변수:
  // - viewModel: 사용자 설정과 처방전 입력 요청을 제공하는 ViewModel
  // 반환값:
  // - 없음
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
    if (task == MedicationCaptureTask.pill) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PillIdentificationUI(
            userSetting: viewModel.userSetting,
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
          builder: (context) =>
              GuidedPrescriptionCameraUI(userSetting: viewModel.userSetting),
        ),
      );
      if (!mounted || image == null) {
        return;
      }
      Navigator.pop(context);
      await viewModel.requestCapturedPrescriptionImage(image);
      return;
    }
    Navigator.pop(context);
    viewModel.requestPrescriptionImageFromGallery();
  }

  // 함수명: _confirmAndDeleteMedicationGroup
  // 함수역할:
  // - 삭제 확인 팝업을 띄운 뒤 사용자가 승인하면 날짜 그룹의 약들을 삭제한다.
  // - 날짜 그룹 전체를 ViewModel의 일괄 삭제 흐름으로 전달한다.
  // 매개변수:
  // - viewModel: 삭제 API를 호출할 ViewModel
  // - group: 삭제 대상 날짜 그룹
  // - text: 현재 언어에 맞는 저장 목록 문구 묶음
  // 반환값:
  // - 없음
  Future<void> _confirmAndDeleteMedicationGroup({
    required MedBuddyViewModel viewModel,
    required _SavedMedicationGroup group,
    required _SavedMedicationText text,
  }) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withAlpha(115),
      builder: (context) {
        return _DeleteConfirmationDialog(text: text);
      },
    );
    if (shouldDelete != true) {
      return;
    }

    final result = await viewModel.requestDeleteSavedMedications(
      group.medications.map((medication) => medication.id).whereType<int>(),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.deleteResult(result))));
  }

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
        .map((medication) => medication.id)
        .whereType<int>()
        .toSet();
    setState(() {
      _selectedMedicationIds.retainAll(remainingIds);
      _isSelectionMode = _selectedMedicationIds.isNotEmpty;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.deleteResult(result))));
  }

  // 함수명: _showMedicationDetail
  // 함수역할:
  // - 저장된 약의 공공데이터 기반 효능, 복용 방법, 주의사항을 하단 시트로 표시한다.
  // 매개변수:
  // - medication: 가이드를 보여줄 약 정보
  // - text: 현재 언어에 맞는 저장 목록 문구 묶음
  // - userSetting: 글자 크기와 언어 설정
  // 반환값:
  // - 없음
  void _showMedicationDetail({
    required MedicationDetail medication,
    required _SavedMedicationText text,
    required UserSetting userSetting,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckMedicationDetailUI(
          medicationDetail: medication,
          userSetting: userSetting,
        ),
      ),
    );
  }

  // 함수명: _showMedicationImage
  // 함수역할:
  // - 공공데이터 API가 제공한 약품 이미지 URL을 팝업으로 표시한다.
  // - 이미지 URL이 없으면 사용자에게 안내 메시지를 보여준다.
  // 매개변수:
  // - medication: 사진을 보여줄 약 정보
  // - text: 현재 언어에 맞는 저장 목록 문구 묶음
  // - userSetting: 글자 크기와 언어 설정
  // 반환값:
  // - 없음
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
