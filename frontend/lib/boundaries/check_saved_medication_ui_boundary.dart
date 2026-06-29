import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../boundaries/medication_detail_ui_boundary.dart';
import '../entities/medication_detail_entity.dart';
import '../entities/medication_guide_entity.dart';
import '../entities/user_setting_entity.dart';
import '../theme/medbuddy_theme.dart';
import '../viewmodels/medbuddy_view_model.dart';

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

class _CheckSavedMedicationUIState extends State<CheckSavedMedicationUI> {
  final Set<int> _selectedMedicationIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MedBuddyViewModel>().fetchSavedMedicationInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MedBuddyViewModel>();
    final userSetting = viewModel.userSetting;
    final text = _SavedMedicationText(userSetting.language);
    final savedMedicationInfoList = viewModel.savedMedicationInfoList;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(42, 24, 42, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
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
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      text.title,
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
              const SizedBox(height: 26),
              Expanded(
                child: _buildContent(viewModel, savedMedicationInfoList, text),
              ),
            ],
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
        onPrescriptionInputRequested: () {
          _showPrescriptionInputOptions(
            viewModel: viewModel,
            text: text,
          );
        },
      );
    }

    final groups = _SavedMedicationGroup.fromMedicationList(
      savedMedicationInfoList,
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
            _showMedicationGuide(
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

  // 함수명: _showPrescriptionInputOptions
  // 함수역할:
  // - 저장 목록이 비어 있을 때 처방전 입력 방식을 카메라/갤러리 중 선택하게 한다.
  // - 선택 후 저장 목록 화면을 닫고 홈 화면의 분석 흐름으로 이어준다.
  // 매개변수:
  // - viewModel: 처방전 입력 요청을 수행할 ViewModel
  // - text: 현재 언어에 맞는 저장 목록 문구 묶음
  // 반환값:
  // - 없음
  void _showPrescriptionInputOptions({
    required MedBuddyViewModel viewModel,
    required _SavedMedicationText text,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DC),
                    borderRadius: MedBuddyRadii.pill,
                  ),
                ),
                const SizedBox(height: 18),
                _SavedMedicationInputOption(
                  icon: Icons.photo_camera_outlined,
                  title: text.cameraOption,
                  subtitle: text.cameraOptionSubtitle,
                  userSetting: viewModel.userSetting,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.pop(context);
                    viewModel.requestPrescriptionImage();
                  },
                ),
                const SizedBox(height: 10),
                _SavedMedicationInputOption(
                  icon: Icons.photo_library_outlined,
                  title: text.galleryOption,
                  subtitle: text.galleryOptionSubtitle,
                  userSetting: viewModel.userSetting,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.pop(context);
                    viewModel.requestPrescriptionImageFromGallery();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 함수명: _confirmAndDeleteMedicationGroup
  // 함수역할:
  // - 삭제 확인 팝업을 띄운 뒤 사용자가 승인하면 날짜 그룹의 약들을 삭제한다.
  // - 현재 UI는 날짜 카드 단위 삭제를 제공하므로 그룹 내부 약을 순차 삭제한다.
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

    for (final medication in group.medications) {
      final id = medication.id;
      if (id != null) {
        await viewModel.requestDeleteSavedMedication(id);
      }
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.deleted)),
    );
  }

  Future<void> _confirmAndDeleteSelectedMedications({
    required MedBuddyViewModel viewModel,
    required _SavedMedicationText text,
  }) async {
    if (_selectedMedicationIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.noSelection)),
      );
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
    for (final id in selectedIds) {
      await viewModel.requestDeleteSavedMedication(id);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedMedicationIds.clear();
      _isSelectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.deleted)),
    );
  }

  // 함수명: _showMedicationGuide
  // 함수역할:
  // - 저장된 약의 공공데이터 기반 효능, 복용 방법, 주의사항을 하단 시트로 표시한다.
  // 매개변수:
  // - medication: 가이드를 보여줄 약 정보
  // - text: 현재 언어에 맞는 저장 목록 문구 묶음
  // - userSetting: 글자 크기와 언어 설정
  // 반환값:
  // - 없음
  void _showMedicationGuide({
    required MedicationDetail medication,
    required _SavedMedicationText text,
    required UserSetting userSetting,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MedicationDetailUI(
          medicationGuide: MedicationGuide.fromMedicationDetail(medication),
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
    if (medication.imageUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.noImage)),
      );
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

class _SavedMedicationEmptyState extends StatelessWidget {
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final VoidCallback onPrescriptionInputRequested;

  const _SavedMedicationEmptyState({
    required this.text,
    required this.userSetting,
    required this.onPrescriptionInputRequested,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 34, 22, 32),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: MedBuddyRadii.card,
                border: Border.all(color: const Color(0xFFD1D5DC), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.medication_outlined,
                    color: MedBuddyColors.textLight,
                    size: 42,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    text.emptyMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MedBuddyColors.textMuted,
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 178,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MedBuddyColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              shape: RoundedRectangleBorder(
                borderRadius: MedBuddyRadii.card,
              ),
              textStyle: TextStyle(
                fontSize: 22 * scale,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            onPressed: onPrescriptionInputRequested,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.photo_camera_outlined, size: 40),
                const SizedBox(height: 18),
                Text(
                  text.scanPrescription,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  text.scanSubtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MedBuddyColors.mint,
                    fontSize: 14 * scale,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// 클래스명: _SavedMedicationInputOption
// 역할: 저장 목록 빈 상태에서 카메라/갤러리 처방전 입력 선택지를 표시한다.
// 주요 책임:
// - 입력 방식의 아이콘, 제목, 설명을 한 행으로 보여준다.
// - 사용자가 선택한 입력 방식 콜백을 실행한다.
class _SavedMedicationInputOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final UserSetting userSetting;
  final VoidCallback onTap;

  const _SavedMedicationInputOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.userSetting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Material(
      color: const Color(0xFFF4FFF4),
      borderRadius: MedBuddyRadii.card,
      child: InkWell(
        borderRadius: MedBuddyRadii.card,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: MedBuddyRadii.card,
            border: Border.all(color: MedBuddyColors.mint, width: 1.6),
          ),
          child: Row(
            children: [
              Icon(icon, color: MedBuddyColors.primary, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 17 * scale,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 13 * scale,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: MedBuddyColors.primary,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionDeleteBar extends StatelessWidget {
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final int selectedCount;
  final Future<void> Function() onDeleteRequested;

  const _SelectionDeleteBar({
    required this.text,
    required this.userSetting,
    required this.selectedCount,
    required this.onDeleteRequested,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.selectedCount(selectedCount),
              style: TextStyle(
                color: MedBuddyColors.textMuted,
                fontSize: 14 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          FilledButton(
            onPressed:
                selectedCount == 0 ? null : () async => onDeleteRequested(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF1F2D),
              disabledBackgroundColor: const Color(0xFFD1D5DC),
              foregroundColor: Colors.white,
              minimumSize: const Size(118, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: TextStyle(
                fontSize: 14 * scale,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            child: Text(text.deleteSelected),
          ),
        ],
      ),
    );
  }
}

class _SavedMedicationDateCard extends StatelessWidget {
  final _SavedMedicationGroup group;
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final bool isSelectionMode;
  final Set<int> selectedMedicationIds;
  final void Function(MedicationDetail medication, bool selected)
      onSelectionChanged;
  final void Function(MedicationDetail medication) onGuideRequested;
  final void Function(MedicationDetail medication) onImageRequested;
  final Future<void> Function() onDeleteRequested;

  const _SavedMedicationDateCard({
    required this.group,
    required this.text,
    required this.userSetting,
    required this.isSelectionMode,
    required this.selectedMedicationIds,
    required this.onSelectionChanged,
    required this.onGuideRequested,
    required this.onImageRequested,
    required this.onDeleteRequested,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: const Color(0xFFD1D5DC), width: 1.5),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.displayDate,
                    style: TextStyle(
                      color: const Color(0xFF0A0A0A),
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: text.notification,
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(text.notificationComingSoon)),
                    );
                  },
                  icon: const Icon(
                    Icons.notifications_none_outlined,
                    color: MedBuddyColors.textMuted,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFD1D5DC)),
          for (final medication in group.medications) ...[
            _SavedMedicationNameRow(
              medication: medication,
              text: text,
              userSetting: userSetting,
              isSelectionMode: isSelectionMode,
              isSelected: medication.id != null &&
                  selectedMedicationIds.contains(medication.id),
              onSelectionChanged: (selected) {
                onSelectionChanged(medication, selected);
              },
              onGuideRequested: () => onGuideRequested(medication),
              onImageRequested: () => onImageRequested(medication),
            ),
            if (medication != group.medications.last)
              const Divider(height: 1, color: Color(0xFFD1D5DC)),
          ],
          if (!isSelectionMode) ...[
            const Divider(height: 1, color: Color(0xFFD1D5DC)),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(70),
                foregroundColor: const Color(0xFFFF1F2D),
                textStyle: TextStyle(
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              onPressed: onDeleteRequested,
              child: Text(text.delete),
            ),
          ],
        ],
      ),
    );
  }
}

class _SavedMedicationNameRow extends StatelessWidget {
  final MedicationDetail medication;
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final bool isSelectionMode;
  final bool isSelected;
  final void Function(bool selected) onSelectionChanged;
  final VoidCallback onGuideRequested;
  final VoidCallback onImageRequested;

  const _SavedMedicationNameRow({
    required this.medication,
    required this.text,
    required this.userSetting,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onSelectionChanged,
    required this.onGuideRequested,
    required this.onImageRequested,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;
    final dateLineLeftPadding = isSelectionMode ? 52.0 : 0.0;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 124),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isSelectionMode) ...[
                  Checkbox(
                    value: isSelected,
                    activeColor: MedBuddyColors.primary,
                    onChanged: medication.id == null
                        ? null
                        : (value) => onSelectionChanged(value ?? false),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: _MedicationNameButton(
                    medication: medication,
                    text: text,
                    scale: scale,
                    isEnabled: !isSelectionMode,
                    onPressed: onGuideRequested,
                  ),
                ),
                const SizedBox(width: 12),
                _MedicationRowActions(
                  medication: medication,
                  text: text,
                  userSetting: userSetting,
                  onGuideRequested: onGuideRequested,
                  onImageRequested: onImageRequested,
                ),
              ],
            ),
            const SizedBox(height: 7),
            Padding(
              padding: EdgeInsets.only(left: dateLineLeftPadding),
              child: _MedicationDateLine(
                label: text.registeredDate,
                value: _formatMedicationDate(medication.createdDate),
                fallback: text.noInformation,
                scale: scale,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: EdgeInsets.only(left: dateLineLeftPadding),
              child: _MedicationDateLine(
                label: text.medicationPeriod,
                value: _formatMedicationPeriod(medication),
                fallback: text.noInformation,
                scale: scale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 클래스명: _MedicationNameButton
// 역할: 저장 목록의 약품명을 가이드 화면 진입 버튼으로 표시한다.
// 주요 책임:
// - 약품명을 두 줄까지 보여주고 길면 말줄임 처리한다.
// - 선택 삭제 모드가 아닐 때 약품명 탭으로 가이드 팝업을 연다.
class _MedicationNameButton extends StatelessWidget {
  final MedicationDetail medication;
  final _SavedMedicationText text;
  final double scale;
  final bool isEnabled;
  final VoidCallback onPressed;

  const _MedicationNameButton({
    required this.medication,
    required this.text,
    required this.scale,
    required this.isEnabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = medication.itemName.trim().isEmpty
        ? text.noInformation
        : medication.itemName.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: isEnabled ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFF0A0A0A),
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedicationDateLine extends StatelessWidget {
  final String label;
  final String value;
  final String fallback;
  final double scale;

  const _MedicationDateLine({
    required this.label,
    required this.value,
    required this.fallback,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? fallback : value.trim();

    return Text(
      '$label: $displayValue',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: MedBuddyColors.textLight,
        fontSize: 11 * scale,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}

String _formatMedicationDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  return '${value.year}/${_formatTwoDigits(value.month)}/${_formatTwoDigits(value.day)}';
}

String _formatMedicationPeriod(MedicationDetail medication) {
  final startDate = medication.prescriptionDate;
  if (startDate == null) {
    return '';
  }

  final totalDays = _readTotalDays(medication.totalDays);
  if (totalDays <= 1) {
    return _formatMedicationDate(startDate);
  }

  final endDate = startDate.add(Duration(days: totalDays - 1));
  return '${_formatMedicationDate(startDate)} ~ ${_formatMedicationDate(endDate)}';
}

int _readTotalDays(String totalDays) {
  final match = RegExp(r'\d+').firstMatch(totalDays);
  if (match == null) {
    return 0;
  }
  return int.tryParse(match.group(0) ?? '') ?? 0;
}

String _formatTwoDigits(int value) {
  return value.toString().padLeft(2, '0');
}

class _MedicationRowActions extends StatelessWidget {
  final MedicationDetail medication;
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final VoidCallback onGuideRequested;
  final VoidCallback onImageRequested;

  const _MedicationRowActions({
    required this.medication,
    required this.text,
    required this.userSetting,
    required this.onGuideRequested,
    required this.onImageRequested,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return SizedBox(
      width: 112,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _MedicationGuideButton(
            label: text.guide,
            scale: scale,
            onPressed: onGuideRequested,
          ),
          const SizedBox(width: 6),
          _MedicationImageButton(
            medication: medication,
            text: text,
            scale: scale,
            onPressed: onImageRequested,
          ),
        ],
      ),
    );
  }
}

class _MedicationGuideButton extends StatelessWidget {
  final String label;
  final double scale;
  final VoidCallback onPressed;

  const _MedicationGuideButton({
    required this.label,
    required this.scale,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        fixedSize: const Size(58, 36),
        minimumSize: const Size(58, 36),
        padding: EdgeInsets.zero,
        foregroundColor: MedBuddyColors.primaryDark,
        backgroundColor: const Color(0xFFEFFDF6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(
          fontSize: 11 * scale,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

// 클래스명: _MedicationImageButton
// 역할: 저장된 약품 이미지가 있으면 썸네일을, 없으면 이미지 없음 표시를 보여준다.
// 주요 책임:
// - 이미지 URL이 있으면 약 사진 팝업을 열 수 있는 썸네일을 표시한다.
// - 이미지 URL이 없으면 텍스트 대신 X 아이콘으로 비어 있음을 표현한다.
class _MedicationImageButton extends StatelessWidget {
  final MedicationDetail medication;
  final _SavedMedicationText text;
  final double scale;
  final VoidCallback onPressed;

  const _MedicationImageButton({
    required this.medication,
    required this.text,
    required this.scale,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = medication.imageUrl.trim();
    if (imageUrl.isEmpty) {
      return Tooltip(
        message: text.noImage,
        child: Container(
          width: 48,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.close_rounded,
            color: MedBuddyColors.textLight,
            size: 22,
          ),
        ),
      );
    }

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 48,
        height: 48,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDBEAFE), width: 5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(
                Icons.image_not_supported_outlined,
                color: MedBuddyColors.textLight,
                size: 22,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MedicationImageDialog extends StatelessWidget {
  final MedicationDetail medication;
  final _SavedMedicationText text;
  final UserSetting userSetting;

  const _MedicationImageDialog({
    required this.medication,
    required this.text,
    required this.userSetting,
  });

  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    medication.itemName.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 17 * scale,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: text.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                medication.imageUrl.trim(),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      text.imageLoadFailed,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: MedBuddyColors.textMuted,
                        fontSize: 14 * scale,
                        letterSpacing: 0,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteConfirmationDialog extends StatelessWidget {
  final _SavedMedicationText text;

  const _DeleteConfirmationDialog({required this.text});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: text.close,
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.close, color: MedBuddyColors.textMuted),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text.deleteMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MedBuddyColors.textStrong,
                fontSize: 15,
                height: 1.45,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      foregroundColor: const Color(0xFFFF1F2D),
                      side: const BorderSide(color: Color(0xFFD1D5DC)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(text.yes),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      foregroundColor: MedBuddyColors.textMuted,
                      side: const BorderSide(color: Color(0xFFD1D5DC)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(text.no),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedMedicationGroup {
  final DateTime? date;
  final List<MedicationDetail> medications;

  const _SavedMedicationGroup({
    required this.date,
    required this.medications,
  });

  String get displayDate {
    final value = date ?? DateTime.now();
    return '${value.year}/${_twoDigits(value.month)}/${_twoDigits(value.day)}';
  }

  static List<_SavedMedicationGroup> fromMedicationList(
    List<MedicationDetail> medicationList,
  ) {
    final groupedMedications = <String, List<MedicationDetail>>{};
    for (final medication in medicationList) {
      final dateKey = _dateKey(medication.createdDate);
      groupedMedications.putIfAbsent(dateKey, () => []).add(medication);
    }

    final groups = groupedMedications.entries.map((entry) {
      return _SavedMedicationGroup(
        date: DateTime.tryParse(entry.key),
        medications: entry.value,
      );
    }).toList(growable: false);

    return groups
      ..sort((left, right) {
        final leftDate = left.date ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate = right.date ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });
  }

  static String _dateKey(DateTime? date) {
    final value = date ?? DateTime.now();
    return '${value.year}-${_twoDigits(value.month)}-${_twoDigits(value.day)}';
  }

  static String _twoDigits(int value) {
    return value.toString().padLeft(2, '0');
  }
}

class _SavedMedicationText {
  final String language;

  const _SavedMedicationText(this.language);

  bool get isEnglish => language == 'en';

  String get title => isEnglish ? 'Saved Medication' : '저장된 복약 정보';
  String get close => isEnglish ? 'Close' : '닫기';
  String get select => isEnglish ? 'Select' : '선택';
  String get done => isEnglish ? 'Done' : '완료';
  String get emptyMessage =>
      isEnglish ? 'No saved medication information.' : '저장된 복약정보가 없습니다.';
  String get scanPrescription => isEnglish ? 'Scan Prescription' : '처방전 촬영하기';
  String get scanSubtitle => isEnglish
      ? 'Take a photo or choose one from your gallery'
      : '카메라 또는 갤러리에서 처방전을 추가해주세요';
  String get cameraOption => isEnglish ? 'Take Photo' : '카메라로 촬영';
  String get cameraOptionSubtitle =>
      isEnglish ? 'Take a prescription photo now.' : '처방전을 바로 촬영합니다.';
  String get galleryOption => isEnglish ? 'Choose From Gallery' : '갤러리에서 선택';
  String get galleryOptionSubtitle =>
      isEnglish ? 'Load a saved prescription image.' : '저장된 처방전 이미지를 불러옵니다.';
  String get notification => isEnglish ? 'Notification' : '알림 설정';
  String get notificationComingSoon =>
      isEnglish ? 'Notifications are coming soon.' : '알림 설정은 준비 중입니다.';
  String get noInformation => isEnglish ? 'No information' : '정보 없음';
  String get registeredDate => isEnglish ? 'Registered' : '등록일자';
  String get medicationPeriod => isEnglish ? 'Medication period' : '복용기간';
  String get photo => isEnglish ? 'Photo' : '사진';
  String get noImage =>
      isEnglish ? 'No medication image is available.' : '제공된 약 사진이 없습니다.';
  String get imageLoadFailed => isEnglish
      ? 'The medication image could not be loaded.'
      : '약 사진을 불러올 수 없습니다.';
  String get guide => isEnglish ? 'Guide' : '가이드';
  String get efficacy => isEnglish ? 'Effect' : '효능';
  String get usageMethod => isEnglish ? 'How to take' : '복용 방법';
  String get warning => isEnglish ? 'Warnings' : '주의사항';
  String get delete => isEnglish ? 'Delete' : '삭제하기';
  String get deleteSelected => isEnglish ? 'Delete Selected' : '선택 삭제';
  String get noSelection =>
      isEnglish ? 'Select medication to delete.' : '삭제할 약을 선택해주세요.';
  String selectedCount(int count) =>
      isEnglish ? '$count selected' : '$count개 선택됨';
  String get deleted => isEnglish ? 'Deleted.' : '삭제되었습니다.';
  String get deleteMessage => isEnglish
      ? 'Delete this medication information?\nThis action cannot be undone.'
      : '해당 복약 정보를 삭제하시겠습니까?\n되돌릴 수 없습니다.';
  String get yes => isEnglish ? 'Yes' : '예';
  String get no => isEnglish ? 'No' : '아니오';
}
