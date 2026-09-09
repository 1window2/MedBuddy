part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_list_widgets.dart
// 역할: 저장 약품 정렬, 날짜·복용기간 표시 및 상세·사진 진입을 제공한다.

// 클래스명: _SavedMedicationSortControl
// 역할: 저장 날짜 정렬 방향 선택과 전환을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 저장 날짜 정렬 방향 선택과 전환 위젯을 구성한다.
// 속성:
// - sortDirection (_SavedMedicationSortDirection): 날짜 정렬의 오름차순·내림차순 선택.
// - onDirectionChanged (ValueChanged<_SavedMedicationSortDirection>): 변경한 날짜 정렬 방향을 전달할 콜백.
class _SavedMedicationSortControl extends StatelessWidget {
  final _SavedMedicationSortDirection sortDirection;
  final _SavedMedicationText text;
  final ValueChanged<_SavedMedicationSortDirection> onDirectionChanged;

  // 함수이름: _SavedMedicationSortControl
  // 함수역할: 저장 날짜 정렬 방향 선택과 전환에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - sortDirection (_SavedMedicationSortDirection): 날짜 정렬의 오름차순·내림차순 선택.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // - onDirectionChanged (ValueChanged<_SavedMedicationSortDirection>): 변경한 날짜 정렬 방향을 전달할 콜백.
  // 반환값: 입력 설정이 반영된 _SavedMedicationSortControl 인스턴스.
  const _SavedMedicationSortControl({
    required this.sortDirection,
    required this.text,
    required this.onDirectionChanged,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 저장 날짜 정렬 방향 선택과 전환 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 저장 날짜 정렬 방향 선택과 전환에 쓰는 위젯 트리.
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

  // 함수이름: _toggleDirection
  // 함수역할: 현재 날짜 정렬 방향의 반대 값을 선택 콜백으로 전달한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _toggleDirection() {
    final nextDirection =
        sortDirection == _SavedMedicationSortDirection.descending
        ? _SavedMedicationSortDirection.ascending
        : _SavedMedicationSortDirection.descending;
    onDirectionChanged(nextDirection);
  }
}

// 클래스명: _SavedMedicationSortMenuItem
// 역할: 정렬 방향 이름과 현재 선택 표시를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 정렬 방향 이름과 현재 선택 표시 위젯을 구성한다.
// 속성:
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - isSelected (bool): 현재 선택 집합에 포함되는지 여부.
class _SavedMedicationSortMenuItem extends StatelessWidget {
  final String label;
  final bool isSelected;

  // 함수이름: _SavedMedicationSortMenuItem
  // 함수역할: 정렬 방향 이름과 현재 선택 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - isSelected (bool): 현재 선택 집합에 포함되는지 여부.
  // 반환값: 입력 설정이 반영된 _SavedMedicationSortMenuItem 인스턴스.
  const _SavedMedicationSortMenuItem({
    required this.label,
    required this.isSelected,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 정렬 방향 이름과 현재 선택 표시 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 정렬 방향 이름과 현재 선택 표시에 쓰는 위젯 트리.
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

// 클래스명: _SavedMedicationNameRow
// 역할: 약품명·처방일·복용기간과 선택·가이드·사진 동작을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약품명·처방일·복용기간과 선택·가이드·사진 동작 위젯을 구성한다.
// 속성:
// - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - isSelectionMode (bool): 일반 조작 대신 첨부·삭제 선택 모드를 사용할지 여부.
// - isSelected (bool): 현재 선택 집합에 포함되는지 여부.
class _SavedMedicationNameRow extends StatelessWidget {
  final MedicationDetail medication;
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final bool isSelectionMode;
  final bool isSelected;
  final void Function(bool selected) onSelectionChanged;
  final VoidCallback onGuideRequested;
  final VoidCallback onImageRequested;

  // 함수이름: _SavedMedicationNameRow
  // 함수역할: 약품명·처방일·복용기간과 선택·가이드·사진 동작에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - isSelectionMode (bool): 일반 조작 대신 첨부·삭제 선택 모드를 사용할지 여부.
  // - isSelected (bool): 현재 선택 집합에 포함되는지 여부.
  // - onSelectionChanged (void Function(bool selected)): 변경된 값 또는 선택 상태를 소유 화면에 전달할 콜백.
  // - onGuideRequested (VoidCallback): 대상 약품의 상세 정보 또는 복용 가이드를 여는 콜백.
  // - onImageRequested (VoidCallback): 약품 사진을 확대해 표시할 콜백.
  // 반환값: 입력 설정이 반영된 _SavedMedicationNameRow 인스턴스.
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

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약품명·처방일·복용기간과 선택·가이드·사진 동작 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약품명·처방일·복용기간과 선택·가이드·사진 동작에 쓰는 위젯 트리.
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
                        // 함수이름: build.onChanged callback
                        // 함수역할: 약품명·처방일·복용기간과 선택·가이드·사진 동작에서 캡처된 작업 `onSelectionChanged(value ?? false)`을 실행한다.
                        // 매개변수:
                        // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
                        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
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
// 역할: 두 줄 약품명과 선택 삭제 중 비활성화되는 가이드 진입을 담당한다.
// 주요 책임:
// - 약품명을 두 줄까지 보여주고 길면 말줄임 처리한다.
// - 선택 삭제 모드가 아닐 때 약품명 탭으로 가이드 팝업을 연다.
// 속성:
// - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
// - isEnabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
// - onPressed (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _MedicationNameButton extends StatelessWidget {
  final MedicationDetail medication;
  final _SavedMedicationText text;
  final double scale;
  final bool isEnabled;
  final VoidCallback onPressed;

  // 함수이름: _MedicationNameButton
  // 함수역할: 두 줄 약품명과 선택 삭제 중 비활성화되는 가이드 진입에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - isEnabled (bool): 선택지·명령·기능을 사용할 수 있는지 여부.
  // - onPressed (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _MedicationNameButton 인스턴스.
  const _MedicationNameButton({
    required this.medication,
    required this.text,
    required this.scale,
    required this.isEnabled,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 두 줄 약품명과 선택 삭제 중 비활성화되는 가이드 진입 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 두 줄 약품명과 선택 삭제 중 비활성화되는 가이드 진입에 쓰는 위젯 트리.
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

// 클래스명: _MedicationDateLine
// 역할: 날짜 제목·값과 날짜 부재 대체 표시를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 날짜 제목·값과 날짜 부재 대체 표시 위젯을 구성한다.
// 속성:
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
// - fallback (String): 값이나 약품 정보를 제공할 수 없을 때 사용할 대체 문구.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _MedicationDateLine extends StatelessWidget {
  final String label;
  final String value;
  final String fallback;
  final double scale;

  // 함수이름: _MedicationDateLine
  // 함수역할: 날짜 제목·값과 날짜 부재 대체 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // - fallback (String): 값이나 약품 정보를 제공할 수 없을 때 사용할 대체 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _MedicationDateLine 인스턴스.
  const _MedicationDateLine({
    required this.label,
    required this.value,
    required this.fallback,
    required this.scale,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 날짜 제목·값과 날짜 부재 대체 표시 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 날짜 제목·값과 날짜 부재 대체 표시에 쓰는 위젯 트리.
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

// 함수이름: _formatMedicationDate
// 함수역할: 날짜를 연/월/일로 표시하고 null이면 빈 문자열을 반환한다.
// 매개변수:
// - value (DateTime?): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
// 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
String _formatMedicationDate(DateTime? value) {
  if (value == null) {
    return '';
  }
  return '${value.year}/${_formatTwoDigits(value.month)}/${_formatTwoDigits(value.day)}';
}

// 함수이름: _formatMedicationPeriod
// 함수역할: 처방일부터 투약일수-1일까지의 기간을 표시하며 하루 이하는 시작일만 표시한다.
// 매개변수:
// - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
// 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
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

// 함수이름: _readTotalDays
// 함수역할: 투약일 문구의 첫 정수를 읽고 숫자가 없거나 파싱 실패 시 0을 사용한다.
// 매개변수:
// - totalDays (String): 복용 기간의 일수 또는 이를 표현한 원본 문구.
// 반환값: int: 문자열에서 읽은 첫 정수; 숫자가 없거나 변환에 실패하면 0.
int _readTotalDays(String totalDays) {
  final match = RegExp(r'\d+').firstMatch(totalDays);
  if (match == null) {
    return 0;
  }
  return int.tryParse(match.group(0) ?? '') ?? 0;
}

// 함수이름: _formatTwoDigits
// 함수역할: 숫자 왼쪽을 0으로 채워 최소 두 자리로 표시한다.
// 매개변수:
// - value (int): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
// 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
String _formatTwoDigits(int value) {
  return value.toString().padLeft(2, '0');
}

// 클래스명: _MedicationRowActions
// 역할: 저장 약품의 가이드와 사진 명령을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 저장 약품의 가이드와 사진 명령 위젯을 구성한다.
// 속성:
// - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - onGuideRequested (VoidCallback): 대상 약품의 상세 정보 또는 복용 가이드를 여는 콜백.
// - onImageRequested (VoidCallback): 약품 사진을 확대해 표시할 콜백.
class _MedicationRowActions extends StatelessWidget {
  final MedicationDetail medication;
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final VoidCallback onGuideRequested;
  final VoidCallback onImageRequested;

  // 함수이름: _MedicationRowActions
  // 함수역할: 저장 약품의 가이드와 사진 명령에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - onGuideRequested (VoidCallback): 대상 약품의 상세 정보 또는 복용 가이드를 여는 콜백.
  // - onImageRequested (VoidCallback): 약품 사진을 확대해 표시할 콜백.
  // 반환값: 입력 설정이 반영된 _MedicationRowActions 인스턴스.
  const _MedicationRowActions({
    required this.medication,
    required this.text,
    required this.userSetting,
    required this.onGuideRequested,
    required this.onImageRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 저장 약품의 가이드와 사진 명령 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 저장 약품의 가이드와 사진 명령에 쓰는 위젯 트리.
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

// 클래스명: _MedicationDetailButton
// 역할: 저장 약의 복용 가이드 열기를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 저장 약의 복용 가이드 열기 위젯을 구성한다.
// 속성:
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
// - onPressed (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _MedicationDetailButton extends StatelessWidget {
  final String label;
  final double scale;
  final VoidCallback onPressed;

  // 함수이름: _MedicationDetailButton
  // 함수역할: 저장 약의 복용 가이드 열기에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - onPressed (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _MedicationDetailButton 인스턴스.
  const _MedicationDetailButton({
    required this.label,
    required this.scale,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 저장 약의 복용 가이드 열기 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 저장 약의 복용 가이드 열기에 쓰는 위젯 트리.
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
// 역할: 저장 약 이미지 썸네일과 사진 없음 표시를 담당한다.
// 주요 책임:
// - 이미지 URL이 있으면 약 사진 팝업을 열 수 있는 썸네일을 표시한다.
// - 이미지 URL이 없으면 텍스트 대신 X 아이콘으로 비어 있음을 표현한다.
// 속성:
// - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
// - onPressed (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
class _MedicationImageButton extends StatelessWidget {
  final MedicationDetail medication;
  final _SavedMedicationText text;
  final double scale;
  final VoidCallback onPressed;

  // 함수이름: _MedicationImageButton
  // 함수역할: 저장 약 이미지 썸네일과 사진 없음 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
  // - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - onPressed (VoidCallback): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // 반환값: 입력 설정이 반영된 _MedicationImageButton 인스턴스.
  const _MedicationImageButton({
    required this.medication,
    required this.text,
    required this.scale,
    required this.onPressed,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 저장 약 이미지 썸네일과 사진 없음 표시 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 저장 약 이미지 썸네일과 사진 없음 표시에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final imageUrl = safeMedicationImageUrl(medication.imageUrl);
    final localImageFile = medication.localImagePath.trim().isEmpty
        ? null
        : File(medication.localImagePath.trim());
    final hasLocalImage = localImageFile?.existsSync() ?? false;
    if (!hasLocalImage && imageUrl.isEmpty) {
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
      key: ValueKey('savedMedicationImage-${medication.id}'),
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
          child: hasLocalImage
              ? Image.file(
                  localImageFile!,
                  fit: BoxFit.cover,
                  errorBuilder: _buildMedicationImageError,
                )
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: _buildMedicationImageError,
                ),
        ),
      ),
    );
  }

  // 함수이름: _buildMedicationImageError
  // 함수역할: 썸네일 로드 오류를 사진 없음 아이콘으로 표시한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // - error (Object): 사용자 안내 또는 복구 분기에 사용할 실패 정보.
  // - stackTrace (StackTrace?): 이미지 로드 실패 지점의 선택적 호출 스택; 표시에는 사용하지 않음.
  // 반환값: 저장 약 이미지 썸네일과 사진 없음 표시에 쓰는 위젯 트리.
  Widget _buildMedicationImageError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return const Icon(
      Icons.image_not_supported_outlined,
      color: MedBuddyColors.textLight,
      size: 22,
    );
  }
}
