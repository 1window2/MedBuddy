part of 'check_saved_medication_ui_boundary.dart';

// 파일명: check_saved_medication_list_widgets.dart
// 역할: 저장 약품 정렬, 날짜·복용기간 표시 및 상세·사진 진입을 제공한다.

// 클래스명: _SavedMedicationNameRow
// 역할: 약 사진·약품명·등록일·복용기간을 한 줄 목록 항목으로 보여 주고 선택·가이드·사진 동작을 연결한다.
// 주요 책임:
// - 일반 모드에서는 항목 전체를 눌러 복약 가이드를 열고 사진은 따로 확대한다.
// - 선택 모드에서는 체크박스로만 선택을 바꾸고 가이드·사진 동작을 막는다.
// 속성:
// - showRegisteredDate (bool): 등록일 줄을 함께 표시할지 여부.
// - medication (MedicationDetail): 표시·변환·저장·비교할 약품 데이터.
// - text (_SavedMedicationText): 해당 화면 구역의 언어별 표시 문구.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - isSelectionMode (bool): 일반 조작 대신 첨부·삭제 선택 모드를 사용할지 여부.
// - enabled (bool): 삭제 중이 아니어서 조작할 수 있는지 여부.
// - isSelected (bool): 현재 선택 집합에 포함되는지 여부.
// - onSelectionChanged (void Function(bool selected)): 선택 상태 변경을 소유 화면에 전달할 콜백.
// - onGuideRequested (VoidCallback): 복약 가이드를 여는 콜백.
// - onImageRequested (VoidCallback): 약품 사진을 확대해 표시할 콜백.
class _SavedMedicationNameRow extends StatelessWidget {
  final bool showRegisteredDate;
  final MedicationDetail medication;
  final _SavedMedicationText text;
  final UserSetting userSetting;
  final bool isSelectionMode;
  final bool enabled;
  final bool isSelected;
  final void Function(bool selected) onSelectionChanged;
  final VoidCallback onGuideRequested;
  final VoidCallback onImageRequested;

  // 함수이름: _SavedMedicationNameRow
  // 함수역할: 목록 항목 표시와 동작에 필요한 입력값을 보관한다.
  // 매개변수: 클래스 속성 설명과 같다.
  // 반환값: 입력 설정이 반영된 _SavedMedicationNameRow 인스턴스.
  const _SavedMedicationNameRow({
    required this.showRegisteredDate,
    required this.medication,
    required this.text,
    required this.userSetting,
    required this.isSelectionMode,
    required this.enabled,
    required this.isSelected,
    required this.onSelectionChanged,
    required this.onGuideRequested,
    required this.onImageRequested,
  });

  // 함수이름: build
  // 함수역할: 사진·이름·날짜와 이동 표시를 가로로 배치한 목록 항목을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 저장 약 한 건의 목록 항목 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;
    final interactive = enabled && !isSelectionMode;
    final displayName = medication.itemName.trim().isEmpty
        ? text.noInformation
        : medication.itemName.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: interactive ? onGuideRequested : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(isSelectionMode ? 6 : 16, 14, 8, 14),
          child: Row(
            children: [
              if (isSelectionMode)
                Checkbox(
                  key: ValueKey('saved-medication-checkbox-${medication.id}'),
                  semanticLabel: medication.itemName,
                  value: isSelected,
                  activeColor: MedBuddyColors.primary,
                  onChanged: !enabled || (medication.id ?? 0) <= 0
                      ? null
                      : (value) => onSelectionChanged(value ?? false),
                ),
              MedicationThumbnail(
                imageUrl: medication.imageUrl,
                localImagePath: medication.localImagePath,
                onTap: interactive ? onImageRequested : null,
                tapKey: ValueKey('savedMedicationImage-${medication.id}'),
                missingImageTooltip: text.noImage,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MedBuddyColors.textStrong,
                        fontSize: 16 * scale,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    if (showRegisteredDate) ...[
                      const SizedBox(height: 4),
                      _MedicationDateLine(
                        label: text.registeredDate,
                        value: _formatMedicationDate(medication.createdDate),
                        fallback: text.noInformation,
                        scale: scale,
                      ),
                    ],
                    const SizedBox(height: 4),
                    _MedicationDateLine(
                      label: text.medicationPeriod,
                      value: _formatMedicationPeriod(medication),
                      fallback: text.noInformation,
                      scale: scale,
                    ),
                  ],
                ),
              ),
              if (!isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: interactive
                        ? MedBuddyColors.textSubtle
                        : MedBuddyColors.textLight,
                    size: 24 * scale,
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
  // 함수역할: 날짜 제목과 전체 값을 읽기 쉬운 대비로 표시하고 큰 글씨에서는 줄바꿈한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 날짜 제목·값과 날짜 부재 대체 표시에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? fallback : value.trim();

    return Text(
      '$label: $displayValue',
      softWrap: true,
      style: TextStyle(
        color: MedBuddyColors.textMuted,
        fontSize: 13 * scale,
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
// 함수역할: 처방일부터 투약일수-1일까지의 기간을 표시하며 하루 이하는 시작일만, 같은 해에 끝나면 끝 날짜의 연도를 생략한다.
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
  // 같은 해에 끝나면 끝 날짜의 연도를 생략해 한 줄에 들어가게 한다.
  final endText = endDate.year == startDate.year
      ? '${_formatTwoDigits(endDate.month)}/${_formatTwoDigits(endDate.day)}'
      : _formatMedicationDate(endDate);
  return '${_formatMedicationDate(startDate)} ~ $endText';
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
