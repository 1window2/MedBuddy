part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_support.dart
// 역할: 이미지·삭제 대화상자와 날짜 그룹, 화면 문구 모델을 제공한다.

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
    final imageUrl = safeMedicationImageUrl(medication.imageUrl);
    final screenSize = MediaQuery.sizeOf(context);

    return Dialog(
      key: const Key('medication-image-dialog'),
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: screenSize.height * 0.85,
        ),
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
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: InteractiveViewer(
                    key: const Key('medication-image-viewer'),
                    minScale: 1,
                    maxScale: 4,
                    child: Image.network(
                      imageUrl,
                      width: double.infinity,
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
                ),
              ),
            ],
          ),
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
                      side: const BorderSide(color: MedBuddyColors.outline),
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
                      side: const BorderSide(color: MedBuddyColors.outline),
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

  const _SavedMedicationGroup({required this.date, required this.medications});

  String get displayDate {
    final value = date ?? DateTime.now();
    return '${value.year}/${_twoDigits(value.month)}/${_twoDigits(value.day)}';
  }

  static List<_SavedMedicationGroup> fromMedicationList(
    List<MedicationDetail> medicationList, {
    required _SavedMedicationSortMode sortMode,
    required _SavedMedicationSortDirection sortDirection,
  }) {
    final groupedMedications = <String, List<MedicationDetail>>{};
    for (final medication in medicationList) {
      final groupDate = _dateForSortMode(medication, sortMode);
      final dateKey = _dateKey(groupDate);
      groupedMedications.putIfAbsent(dateKey, () => []).add(medication);
    }

    final groups = groupedMedications.entries
        .map((entry) {
          return _SavedMedicationGroup(
            date: DateTime.tryParse(entry.key),
            medications: entry.value,
          );
        })
        .toList(growable: false);

    return groups..sort((left, right) {
      final leftDate = left.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightDate = right.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (sortDirection == _SavedMedicationSortDirection.ascending) {
        return leftDate.compareTo(rightDate);
      }
      return rightDate.compareTo(leftDate);
    });
  }

  // 함수명: _dateForSortMode
  // 함수역할:
  // - 선택한 기준에 맞는 그룹 날짜를 반환하고 복용일이 없으면 등록일을 사용한다.
  static DateTime? _dateForSortMode(
    MedicationDetail medication,
    _SavedMedicationSortMode sortMode,
  ) {
    if (sortMode == _SavedMedicationSortMode.medicationDate) {
      return medication.prescriptionDate ?? medication.createdDate;
    }
    return medication.createdDate;
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
  String get sortByRegisteredDate => isEnglish ? 'Registration date' : '등록일자순';
  String get sortByMedicationDate => isEnglish ? 'Medication date' : '복용날짜순';
  String get sortSettings => isEnglish ? 'Sort settings' : '정렬 기준 설정';
  String get ascendingOrder => isEnglish ? 'Oldest first' : '오름차순';
  String get descendingOrder => isEnglish ? 'Newest first' : '내림차순';
  String get changeSortDirection =>
      isEnglish ? 'Change sort direction' : '정렬 방향 변경';
  String get activeMedication => isEnglish ? 'Active' : '복용 중';
  String get endedMedication => isEnglish ? 'Ended' : '복용 종료';
  String get allMedication => isEnglish ? 'All' : '전체';
  String filteredEmptyMessage(_SavedMedicationFilterMode filterMode) {
    return switch (filterMode) {
      _SavedMedicationFilterMode.active =>
        isEnglish ? 'No medication is active today.' : '현재 복용 중인 약이 없습니다.',
      _SavedMedicationFilterMode.ended =>
        isEnglish ? 'No completed medication history.' : '복용이 끝난 약이 없습니다.',
      _SavedMedicationFilterMode.all => emptyMessage,
    };
  }

  String get emptyMessage =>
      isEnglish ? 'No saved medication information.' : '저장된 복약정보가 없습니다.';
  String get scanPrescription => isEnglish ? 'Scan Prescription' : '처방전 촬영하기';
  String get scanSubtitle => isEnglish
      ? 'Choose prescription analysis or loose-pill identification'
      : '처방전 분석 또는 낱알약 식별을 선택해주세요';
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
  String deleteResult(SavedMedicationBatchDeleteResult result) {
    if (result.totalCount == 0) {
      return noSelection;
    }
    if (result.allSucceeded) {
      return deleted;
    }
    return isEnglish
        ? 'Deleted: ${result.successCount}. Failed: ${result.failureCount}.'
        : '삭제 성공: ${result.successCount}개. 실패: ${result.failureCount}개.';
  }

  String get deleteMessage => isEnglish
      ? 'Delete this medication information?\nThis action cannot be undone.'
      : '해당 복약 정보를 삭제하시겠습니까?\n되돌릴 수 없습니다.';
  String get yes => isEnglish ? 'Yes' : '예';
  String get no => isEnglish ? 'No' : '아니오';
}
