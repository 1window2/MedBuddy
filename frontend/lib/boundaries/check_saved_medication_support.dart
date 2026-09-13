part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_support.dart
// 역할: 저장 약품 사진·삭제 대화상자, 날짜 그룹 및 현지화 문구를 제공한다.

// 클래스명: _MedicationImageDialog
// 역할: 저장 약 사진과 불러오기 실패 안내를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 저장 약 사진과 불러오기 실패 안내 위젯을 구성한다.
// 속성:
// - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
class _MedicationImageDialog extends StatelessWidget {
  final MedicationDetail medication;
  final _SavedMedicationText text;
  final UserSetting userSetting;

  // 함수이름: _MedicationImageDialog
  // 함수역할: 저장 약 사진과 불러오기 실패 안내에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // 반환값: 입력 설정이 반영된 _MedicationImageDialog 인스턴스.
  const _MedicationImageDialog({
    required this.medication,
    required this.text,
    required this.userSetting,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 저장 약 사진과 불러오기 실패 안내 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 저장 약 사진과 불러오기 실패 안내에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;
    final imageUrl = safeMedicationImageUrl(medication.imageUrl);
    final localImageFile = medication.localImagePath.trim().isEmpty
        ? null
        : File(medication.localImagePath.trim());
    final hasLocalImage = localImageFile?.existsSync() ?? false;
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
                    // 함수이름: build.onPressed callback
                    // 함수역할: `Navigator.pop(context)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
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
                    child: hasLocalImage
                        ? Image.file(
                            localImageFile!,
                            width: double.infinity,
                            fit: BoxFit.contain,
                            // 함수이름: build.errorBuilder callback
                            // 함수역할: 이미지를 해석하거나 불러올 수 없으면 사진 없음 대체 표시를 구성한다.
                            // 매개변수:
                            // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
                            // - error (콜백 계약에서 추론): 사용자 안내 또는 복구 분기에 사용할 실패 정보.
                            // - stackTrace (콜백 계약에서 추론): 이미지 로드 실패 지점의 선택적 호출 스택; 표시에는 사용하지 않음.
                            // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                            errorBuilder: (context, error, stackTrace) =>
                                _buildImageLoadFailure(scale),
                          )
                        : Image.network(
                            imageUrl,
                            width: double.infinity,
                            fit: BoxFit.contain,
                            // 함수이름: build.errorBuilder callback
                            // 함수역할: 이미지를 해석하거나 불러올 수 없으면 사진 없음 대체 표시를 구성한다.
                            // 매개변수:
                            // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
                            // - error (콜백 계약에서 추론): 사용자 안내 또는 복구 분기에 사용할 실패 정보.
                            // - stackTrace (콜백 계약에서 추론): 이미지 로드 실패 지점의 선택적 호출 스택; 표시에는 사용하지 않음.
                            // 반환값: 설명한 구역 또는 대체 표시의 위젯 트리.
                            errorBuilder: (context, error, stackTrace) =>
                                _buildImageLoadFailure(scale),
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

  // 함수이름: _buildImageLoadFailure
  // 함수역할: 약 사진 대화상자에 현재 글씨 배율로 불러오기 실패 문구를 표시한다.
  // 매개변수:
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 저장 약 사진과 불러오기 실패 안내에 쓰는 위젯 트리.
  Widget _buildImageLoadFailure(double scale) {
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
  }
}

// 클래스명: _DeleteConfirmationDialog
// 역할: 약품 삭제 확정·취소 선택을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약품 삭제 확정·취소 선택 위젯을 구성한다.
class _DeleteConfirmationDialog extends StatelessWidget {
  final _SavedMedicationText text;

  // 함수이름: _DeleteConfirmationDialog
  // 함수역할: 약품 삭제 확정·취소 선택에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // 반환값: 입력 설정이 반영된 _DeleteConfirmationDialog 인스턴스.
  const _DeleteConfirmationDialog({required this.text});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약품 삭제 확정·취소 선택 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약품 삭제 확정·취소 선택에 쓰는 위젯 트리.
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
                // 함수이름: build.onPressed callback
                // 함수역할: `Navigator.pop(context, false)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                // 매개변수:
                // - 없음.
                // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
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
                    // 함수이름: build.onPressed callback
                    // 함수역할: `Navigator.pop(context, true)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
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
                    // 함수이름: build.onPressed callback
                    // 함수역할: `Navigator.pop(context, false)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
                    // 매개변수:
                    // - 없음.
                    // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
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

// 클래스명: _SavedMedicationGroup
// 역할: 같은 날짜에 속한 약품 묶음을 담당한다.
// 주요 책임:
// - 그룹 날짜를 연/월/일로 표시하고 날짜가 없으면 오늘을 사용한다.
// - 선택 날짜 기준으로 약품을 묶고 지정한 오름차순·내림차순으로 그룹을 정렬한다.
// 속성:
// - date (DateTime?): 표시·비교 기준이 되는 날짜 또는 이전·현재 값.
// - medications (List<MedicationDetail>): 조회·선택·정렬·표시에 사용할 약품 목록.
class _SavedMedicationGroup {
  final DateTime? date;
  final List<MedicationDetail> medications;

  // 함수이름: _SavedMedicationGroup
  // 함수역할: 같은 날짜에 속한 약품 묶음 관련 값을 _SavedMedicationGroup 인스턴스에 담는다.
  // 매개변수:
  // - date (DateTime?): 표시·비교 기준이 되는 날짜 또는 이전·현재 값.
  // - medications (List<MedicationDetail>): 조회·선택·정렬·표시에 사용할 약품 목록.
  // 반환값: 입력 설정이 반영된 _SavedMedicationGroup 인스턴스.
  const _SavedMedicationGroup({required this.date, required this.medications});

  // 함수이름: displayDate
  // 함수역할: 그룹 날짜를 연/월/일로 표시하고 날짜가 없으면 오늘을 사용한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get displayDate {
    final value = date ?? DateTime.now();
    return '${value.year}/${_twoDigits(value.month)}/${_twoDigits(value.day)}';
  }

  // 함수이름: fromMedicationList
  // 함수역할: 선택 날짜 기준으로 약품을 묶고 지정한 오름차순·내림차순으로 그룹을 정렬한다.
  // 매개변수:
  // - medicationList (List<MedicationDetail>): 조회·선택·정렬·표시에 사용할 약품 목록.
  // - sortMode (_SavedMedicationSortMode): 약품 등록일 또는 처방일 정렬 기준.
  // - sortDirection (_SavedMedicationSortDirection): 날짜 정렬의 오름차순·내림차순 선택.
  // 반환값: List<_SavedMedicationGroup>: 선택한 날짜 기준·방향으로 정렬한 약품 그룹.
  static List<_SavedMedicationGroup> fromMedicationList(
    List<MedicationDetail> medicationList, {
    required _SavedMedicationSortMode sortMode,
    required _SavedMedicationSortDirection sortDirection,
  }) {
    final groupedMedications = <String, List<MedicationDetail>>{};
    for (final medication in medicationList) {
      final groupDate = _dateForSortMode(medication, sortMode);
      final dateKey = _dateKey(groupDate);
      // 함수이름: fromMedicationList.putIfAbsent callback
      // 함수역할: 같은 날짜에 속한 약품 묶음의 새 키의 초기값을 `[]` 규칙으로 계산한다.
      // 매개변수:
      // - 없음.
      // 반환값: 컬렉션 연산에 전달할 새 키의 초기값.
      groupedMedications.putIfAbsent(dateKey, () => []).add(medication);
    }

    final groups = groupedMedications.entries
        // 함수이름: fromMedicationList.map callback
        // 함수역할: 같은 날짜에 속한 약품 묶음의 변환값을 `_SavedMedicationGroup(date: DateTime.tryParse(entry.key), medications: entry.value)` 규칙으로 계산한다.
        // 매개변수:
        // - entry (콜백 계약에서 추론): 날짜 그룹 키와 해당 약품 목록의 Map 항목.
        // 반환값: 컬렉션 연산에 전달할 변환값.
        .map((entry) {
          return _SavedMedicationGroup(
            date: DateTime.tryParse(entry.key),
            medications: entry.value,
          );
        })
        .toList(growable: false);

    // 함수이름: fromMedicationList.sort callback
    // 함수역할: 같은 날짜에 속한 약품 묶음의 정렬 비교값을 `leftDate.compareTo(rightDate); rightDate.compareTo(leftDate)` 규칙으로 계산한다.
    // 매개변수:
    // - left (콜백 계약에서 추론): 정렬 순서를 비교할 두 항목 중 해당 항목.
    // - right (콜백 계약에서 추론): 정렬 순서를 비교할 두 항목 중 해당 항목.
    // 반환값: 컬렉션 연산에 전달할 정렬 비교값.
    return groups..sort((left, right) {
      final leftDate = left.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightDate = right.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (sortDirection == _SavedMedicationSortDirection.ascending) {
        return leftDate.compareTo(rightDate);
      }
      return rightDate.compareTo(leftDate);
    });
  }

  // 함수이름: _dateForSortMode
  // 함수역할: 선택한 기준에 맞는 그룹 날짜를 반환하고 복용일이 없으면 등록일을 사용한다.
  // 매개변수:
  // - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
  // - sortMode (_SavedMedicationSortMode): 약품 등록일 또는 처방일 정렬 기준.
  // 반환값: DateTime?: 유효한 달력 날짜; 형식·날짜가 잘못되면 null.
  static DateTime? _dateForSortMode(
    MedicationDetail medication,
    _SavedMedicationSortMode sortMode,
  ) {
    if (sortMode == _SavedMedicationSortMode.medicationDate) {
      return medication.prescriptionDate ?? medication.createdDate;
    }
    return medication.createdDate;
  }

  // 함수이름: _dateKey
  // 함수역할: 날짜의 시각을 제외한 연-월-일 키를 만들고 날짜가 없으면 오늘을 사용한다.
  // 매개변수:
  // - date (DateTime?): 표시·비교 기준이 되는 날짜 또는 이전·현재 값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  static String _dateKey(DateTime? date) {
    final value = date ?? DateTime.now();
    return '${value.year}-${_twoDigits(value.month)}-${_twoDigits(value.day)}';
  }

  // 함수이름: _twoDigits
  // 함수역할: 숫자 왼쪽을 0으로 채워 최소 두 자리로 표시한다.
  // 매개변수:
  // - value (int): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  static String _twoDigits(int value) {
    return value.toString().padLeft(2, '0');
  }
}

// 클래스명: _SavedMedicationText
// 역할: 저장 약품 사진·삭제 대화상자, 날짜 그룹 및 현지화 문구에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - 저장 약품 사진·삭제 대화상자, 날짜 그룹 및 현지화 문구에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _SavedMedicationText {
  final String language;

  // 함수이름: _SavedMedicationText
  // 함수역할: 저장 약품 사진·삭제 대화상자, 날짜 그룹 및 현지화 문구에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _SavedMedicationText 인스턴스.
  const _SavedMedicationText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드가 en과 정확히 일치하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language == 'en';

  // 함수이름: title
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장된 복약 정보" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get title => isEnglish ? 'Saved Medication' : '저장된 복약 정보';
  // 함수이름: close
  // 함수역할: 현재 언어와 입력값에 맞춰 "Close" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get close => isEnglish ? 'Close' : '닫기';
  // 함수이름: select
  // 함수역할: 현재 언어와 입력값에 맞춰 "Select" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get select => isEnglish ? 'Select' : '선택';
  // 함수이름: done
  // 함수역할: 현재 언어와 입력값에 맞춰 "Done" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get done => isEnglish ? 'Done' : '완료';
  // 함수이름: sortByRegisteredDate
  // 함수역할: 현재 언어와 입력값에 맞춰 "등록일자순" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get sortByRegisteredDate => isEnglish ? 'Registration date' : '등록일자순';
  // 함수이름: sortByMedicationDate
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용날짜순" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get sortByMedicationDate => isEnglish ? 'Medication date' : '복용날짜순';
  // 함수이름: sortSettings
  // 함수역할: 현재 언어와 입력값에 맞춰 "정렬 기준 설정" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get sortSettings => isEnglish ? 'Sort settings' : '정렬 기준 설정';
  // 함수이름: ascendingOrder
  // 함수역할: 현재 언어와 입력값에 맞춰 "오름차순" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get ascendingOrder => isEnglish ? 'Oldest first' : '오름차순';
  // 함수이름: descendingOrder
  // 함수역할: 현재 언어와 입력값에 맞춰 "내림차순" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get descendingOrder => isEnglish ? 'Newest first' : '내림차순';
  // 함수이름: changeSortDirection
  // 함수역할: 현재 언어와 입력값에 맞춰 "정렬 방향 변경" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get changeSortDirection =>
      isEnglish ? 'Change sort direction' : '정렬 방향 변경';
  // 함수이름: activeMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 중" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get activeMedication => isEnglish ? 'Active' : '복용 중';
  // 함수이름: endedMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 종료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get endedMedication => isEnglish ? 'Ended' : '복용 종료';
  // 함수이름: allMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "All" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get allMedication => isEnglish ? 'All' : '전체';

  // 함수이름: filterTitle
  // 함수역할: 조회 조건 선택 창의 제목을 제공한다. 매개변수: 없음. 반환값: 번역된 제목.
  String get filterTitle => isEnglish ? 'Search filter' : '조회 조건';

  // 함수이름: filterLabel
  // 함수역할: 복용 상태에 해당하는 선택지 이름을 제공한다. 매개변수: mode. 반환값: 번역된 상태명.
  String filterLabel(_SavedMedicationFilterMode mode) => switch (mode) {
    _SavedMedicationFilterMode.active => activeMedication,
    _SavedMedicationFilterMode.ended => endedMedication,
    _SavedMedicationFilterMode.all => allMedication,
  };

  // 함수이름: selectedFilter
  // 함수역할: 현재 조회 조건을 버튼에 표시한다. 매개변수: mode. 반환값: 조건과 선택값을 합친 문구.
  String selectedFilter(_SavedMedicationFilterMode mode) =>
      '$filterTitle: ${filterLabel(mode)}';
  // 함수이름: filteredEmptyMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "현재 복용 중인 약이 없습니다." 문구를 제공한다.
  // 매개변수:
  // - filterMode (_SavedMedicationFilterMode): 저장 약품의 복용 중·종료·전체 표시 기준.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String filteredEmptyMessage(_SavedMedicationFilterMode filterMode) {
    return switch (filterMode) {
      _SavedMedicationFilterMode.active =>
        isEnglish ? 'No medication is active today.' : '현재 복용 중인 약이 없습니다.',
      _SavedMedicationFilterMode.ended =>
        isEnglish ? 'No completed medication history.' : '복용이 끝난 약이 없습니다.',
      _SavedMedicationFilterMode.all => emptyMessage,
    };
  }

  // 함수이름: emptyMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "저장된 복약정보가 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get emptyMessage =>
      isEnglish ? 'No saved medication information.' : '저장된 복약정보가 없습니다.';
  // 함수이름: scanPrescription
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전 촬영하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get scanPrescription => isEnglish ? 'Scan Prescription' : '처방전 촬영하기';
  // 함수이름: scanSubtitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "처방전 분석 또는 낱알약 식별을 선택해주세요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get scanSubtitle => isEnglish
      ? 'Choose prescription analysis or loose-pill identification'
      : '처방전 분석 또는 낱알약 식별을 선택해주세요';
  // 함수이름: noInformation
  // 함수역할: 현재 언어와 입력값에 맞춰 "정보 없음" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noInformation => isEnglish ? 'No information' : '정보 없음';
  // 함수이름: registeredDate
  // 함수역할: 현재 언어와 입력값에 맞춰 "등록일자" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get registeredDate => isEnglish ? 'Registered' : '등록일자';
  // 함수이름: medicationPeriod
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용기간" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationPeriod => isEnglish ? 'Medication period' : '복용기간';
  // 함수이름: photo
  // 함수역할: 현재 언어와 입력값에 맞춰 "Photo" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get photo => isEnglish ? 'Photo' : '사진';
  // 함수이름: noImage
  // 함수역할: 현재 언어와 입력값에 맞춰 "제공된 약 사진이 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noImage =>
      isEnglish ? 'No medication image is available.' : '제공된 약 사진이 없습니다.';
  // 함수이름: imageLoadFailed
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 사진을 불러올 수 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get imageLoadFailed => isEnglish
      ? 'The medication image could not be loaded.'
      : '약 사진을 불러올 수 없습니다.';
  // 함수이름: guide
  // 함수역할: 현재 언어와 입력값에 맞춰 "가이드" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get guide => isEnglish ? 'Guide' : '가이드';
  // 함수이름: efficacy
  // 함수역할: 현재 언어와 입력값에 맞춰 "Effect" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get efficacy => isEnglish ? 'Effect' : '효능';
  // 함수이름: usageMethod
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 방법" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get usageMethod => isEnglish ? 'How to take' : '복용 방법';
  // 함수이름: warning
  // 함수역할: 현재 언어와 입력값에 맞춰 "주의사항" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get warning => isEnglish ? 'Warnings' : '주의사항';
  // 함수이름: delete
  // 함수역할: 현재 언어와 입력값에 맞춰 "삭제하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get delete => isEnglish ? 'Delete' : '삭제하기';
  // 함수이름: deleteSelected
  // 함수역할: 현재 언어와 입력값에 맞춰 "선택 삭제" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deleteSelected => isEnglish ? 'Delete Selected' : '선택 삭제';
  // 함수이름: noSelection
  // 함수역할: 현재 언어와 입력값에 맞춰 "삭제할 약을 선택해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noSelection =>
      isEnglish ? 'Select medication to delete.' : '삭제할 약을 선택해주세요.';
  // 함수이름: selectedCount
  // 함수역할: 현재 언어와 입력값에 맞춰 "$count개 선택됨" 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String selectedCount(int count) =>
      isEnglish ? '$count selected' : '$count개 선택됨';
  // 함수이름: deleted
  // 함수역할: 현재 언어와 입력값에 맞춰 "삭제되었습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deleted => isEnglish ? 'Deleted.' : '삭제되었습니다.';
  // 함수이름: deleteResult
  // 함수역할: 현재 언어와 입력값에 맞춰 "삭제 성공: ${result.successCount}개. 실패: ${result.failureCount}개." 문구를 제공한다.
  // 매개변수:
  // - result (SavedMedicationBatchDeleteResult): 화면에 반영할 작업 결과 또는 요약·추천 데이터.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
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

  // 함수이름: deleteMessage
  // 함수역할: 현재 언어와 입력값에 맞춰 "해당 복약 정보를 삭제하시겠습니까?\n되돌릴 수 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get deleteMessage => isEnglish
      ? 'Delete this medication information?\nThis action cannot be undone.'
      : '해당 복약 정보를 삭제하시겠습니까?\n되돌릴 수 없습니다.';
  // 함수이름: yes
  // 함수역할: 현재 언어와 입력값에 맞춰 "Yes" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get yes => isEnglish ? 'Yes' : '예';
  // 함수이름: no
  // 함수역할: 현재 언어와 입력값에 맞춰 "아니오" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get no => isEnglish ? 'No' : '아니오';
}
