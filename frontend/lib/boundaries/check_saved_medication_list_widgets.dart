part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_list_widgets.dart
// 역할: 정렬 제어와 약품 행, 가이드 및 이미지 버튼 위젯을 구성한다.

class _SavedMedicationSortControl extends StatelessWidget {
  final _SavedMedicationSortDirection sortDirection;
  final _SavedMedicationText text;
  final ValueChanged<_SavedMedicationSortDirection> onDirectionChanged;

  const _SavedMedicationSortControl({
    required this.sortDirection,
    required this.text,
    required this.onDirectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isAscending =
        sortDirection == _SavedMedicationSortDirection.ascending;
    return SizedBox(
      width: 44,
      height: 44,
      child: Semantics(
        button: true,
        label: isAscending ? text.ascendingOrder : text.descendingOrder,
        child: IconButton(
          key: const ValueKey('savedMedicationSortDirectionButton'),
          tooltip: text.changeSortDirection,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(44),
            maximumSize: const Size.square(44),
            foregroundColor: MedBuddyColors.primary,
            backgroundColor: MedBuddyColors.successSurface,
            side: const BorderSide(color: MedBuddyColors.successBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _toggleDirection,
          icon: Icon(
            isAscending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 22,
          ),
        ),
      ),
    );
  }

  // 함수명: _toggleDirection
  // 함수역할:
  // - 오른쪽 화살표를 누르면 현재 날짜 정렬 방향을 반전한다.
  void _toggleDirection() {
    final nextDirection =
        sortDirection == _SavedMedicationSortDirection.descending
        ? _SavedMedicationSortDirection.ascending
        : _SavedMedicationSortDirection.descending;
    onDirectionChanged(nextDirection);
  }
}

// 클래스명: _SavedMedicationSortMenuItem
// 역할: 정렬 설정 메뉴에서 정렬 기준과 현재 선택 상태를 함께 보여준다.
class _SavedMedicationSortMenuItem extends StatelessWidget {
  final String label;
  final bool isSelected;

  const _SavedMedicationSortMenuItem({
    required this.label,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isSelected ? Icons.check_rounded : Icons.calendar_today_outlined,
          color: isSelected ? MedBuddyColors.primary : MedBuddyColors.textMuted,
          size: 20,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: MedBuddyColors.textStrong,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
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
          _MedicationDetailButton(
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

class _MedicationDetailButton extends StatelessWidget {
  final String label;
  final double scale;
  final VoidCallback onPressed;

  const _MedicationDetailButton({
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
    final imageUrl = safeMedicationImageUrl(medication.imageUrl);
    if (imageUrl.isEmpty) {
      return Tooltip(
        message: text.noImage,
        child: Container(
          width: 48,
          height: 36,
          decoration: BoxDecoration(
            color: MedBuddyColors.cardBorder,
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
          border: Border.all(color: MedBuddyColors.imageAccent, width: 5),
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
