part of 'prescription_analysis_preview_ui_boundary.dart';

// 파일명: prescription_preview_medication_widgets.dart
// 역할: OCR 복약 정보 표와 약명·일정 수정 대화상자를 제공한다.

// 클래스명: _MedicationScheduleEditField
// 역할: 표에서 누른 열에 대응하는 초기 입력란을 담당한다.
// 주요 책임:
// - 표에서 누른 열에 대응하는 초기 입력란에서 지원하는 선택지를 열거하고 구분한다: medicationName, dosage, dailyFrequency, totalDays, prescriptionDate, scheduleSlots.
enum _MedicationScheduleEditField {
  medicationName,
  dosage,
  dailyFrequency,
  totalDays,
  prescriptionDate,
  scheduleSlots,
}

// 타입명: _MedicationTableEditCallback
// 역할: 표에서 선택한 행, 복약 일정과 수정할 필드를 화면 상태에 전달한다.
// 함수이름: _MedicationTableEditCallback
// 함수역할: 표의 약품 위치·현재 일정·누른 입력 항목을 편집 동작에 전달하는 계약이다.
// 매개변수:
// - scheduleIndex (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
// - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// - initialField (_MedicationScheduleEditField): 편집 창에서 선택할 복약 정보 입력 항목.
// 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
typedef _MedicationTableEditCallback =
    void Function(
      int scheduleIndex,
      MedicationSchedule medicationSchedule,
      _MedicationScheduleEditField initialField,
    );

// 클래스명: _PreviewMedicationTable
// 역할: 인식된 모든 약의 수정 가능한 가로 스크롤 표를 담당한다.
// 주요 책임:
// - 세로 화면에서도 모든 열을 확인할 수 있도록 표에 가로 스크롤을 제공한다.
// - 각 값 셀을 누르면 해당 입력란이 선택된 수정 창을 연다.
// - 수정 가능 여부와 약명 보정 상태를 화면에서 바로 알아볼 수 있게 한다.
// 속성:
// - medicationScheduleList (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - scrollController (ScrollController): 목록 위치 제어와 스크롤 안내에 사용할 컨트롤러.
// - onEditRequested (_MedicationTableEditCallback): 선택한 약품 일정·입력란의 편집을 여는 콜백.
class _PreviewMedicationTable extends StatelessWidget {
  static const double _tableWidth = 1010;

  final List<MedicationSchedule> medicationScheduleList;
  final _PreviewText previewText;
  final UserSetting userSetting;
  final ScrollController scrollController;
  final _MedicationTableEditCallback onEditRequested;
  final Set<int> verifiedScheduleIndexes;

  // 함수이름: _PreviewMedicationTable
  // 함수역할: 인식된 모든 약의 수정 가능한 가로 스크롤 표에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medicationScheduleList (List<MedicationSchedule>): 검토·표시·시간대 분류에 사용할 복약 일정 목록.
  // - previewText (_PreviewText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - scrollController (ScrollController): 목록 위치 제어와 스크롤 안내에 사용할 컨트롤러.
  // - onEditRequested (_MedicationTableEditCallback): 선택한 약품 일정·입력란의 편집을 여는 콜백.
  // - verifiedScheduleIndexes (Set<int>): 약품 상세 조회로 검증된 일정 인덱스 집합.
  // 반환값: 입력 설정이 반영된 _PreviewMedicationTable 인스턴스.
  const _PreviewMedicationTable({
    required this.medicationScheduleList,
    required this.previewText,
    required this.userSetting,
    required this.scrollController,
    required this.onEditRequested,
    this.verifiedScheduleIndexes = const {},
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 인식된 모든 약의 수정 가능한 가로 스크롤 표 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 인식된 모든 약의 수정 가능한 가로 스크롤 표에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final scale = userSetting.contentTextScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.edit_note_rounded,
              size: 20 * scale,
              color: MedBuddyColors.primaryDark,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                previewText.tableEditGuide,
                style: TextStyle(
                  color: MedBuddyColors.textMuted,
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: MedBuddyColors.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              trackVisibility: true,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: SingleChildScrollView(
                key: const Key('ocr-medication-table-scroll'),
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 11),
                child: SizedBox(
                  width: _tableWidth,
                  child: Table(
                    key: const Key('ocr-medication-table'),
                    border: const TableBorder(
                      horizontalInside: BorderSide(
                        color: MedBuddyColors.outline,
                      ),
                      verticalInside: BorderSide(color: MedBuddyColors.outline),
                    ),
                    columnWidths: const {
                      0: FixedColumnWidth(240),
                      1: FixedColumnWidth(150),
                      2: FixedColumnWidth(150),
                      3: FixedColumnWidth(130),
                      4: FixedColumnWidth(160),
                      5: FixedColumnWidth(180),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      _buildHeaderRow(scale),
                      for (
                        int index = 0;
                        index < medicationScheduleList.length;
                        index++
                      )
                        _buildMedicationRow(
                          index,
                          medicationScheduleList[index],
                          scale,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 함수이름: _buildHeaderRow
  // 함수역할: 약명·용량·횟수·일수·시작일·시간대의 여섯 열 제목을 구성한다.
  // 매개변수:
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: TableRow: 복약 표의 열 제목 또는 편집 가능한 약품 한 행.
  TableRow _buildHeaderRow(double scale) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFEAF8F3)),
      children: [
        _TableHeaderCell(label: previewText.medicationName, scale: scale),
        _TableHeaderCell(label: previewText.dosage, scale: scale),
        _TableHeaderCell(label: previewText.dailyFrequency, scale: scale),
        _TableHeaderCell(label: previewText.totalDays, scale: scale),
        _TableHeaderCell(label: previewText.medicationStartDate, scale: scale),
        _TableHeaderCell(label: previewText.scheduleSlots, scale: scale),
      ],
    );
  }

  // 함수이름: _buildMedicationRow
  // 함수역할: 검증된 일정은 편집을 막고 나머지 여섯 값 셀을 해당 입력란 편집에 연결한다.
  // 매개변수:
  // - scheduleIndex (int): 대상 약품·사진·행의 0부터 시작하는 목록 위치.
  // - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: TableRow: 복약 표의 열 제목 또는 편집 가능한 약품 한 행.
  TableRow _buildMedicationRow(
    int scheduleIndex,
    MedicationSchedule schedule,
    double scale,
  ) {
    final isVerified = verifiedScheduleIndexes.contains(scheduleIndex);
    return TableRow(
      decoration: isVerified
          ? const BoxDecoration(color: Color(0xFFF3F5F4))
          : null,
      children: [
        _EditableMedicationCell(
          cellKey: Key('ocr-table-cell-$scheduleIndex-name'),
          semanticsLabel: previewText.editCell(
            previewText.medicationName,
            schedule.displayNameForLanguage(previewText.language),
          ),
          onTap: isVerified
              ? null
              // 함수이름: _buildMedicationRow.onTap callback
              // 함수역할: 인식된 모든 약의 수정 가능한 가로 스크롤 표에서 캡처된 작업 `onEditRequested(scheduleIndex, schedule, _MedicationScheduleEditField.medicationName)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              : () => onEditRequested(
                  scheduleIndex,
                  schedule,
                  _MedicationScheduleEditField.medicationName,
                ),
          child: _MedicationNameTableValue(
            schedule: schedule,
            previewText: previewText,
            scale: scale,
            isVerified: isVerified,
          ),
        ),
        _EditableMedicationCell(
          cellKey: Key('ocr-table-cell-$scheduleIndex-dosage'),
          semanticsLabel: previewText.editCell(
            previewText.dosage,
            schedule.dosageLabelForLanguage(previewText.language),
          ),
          onTap: isVerified
              ? null
              // 함수이름: _buildMedicationRow.onTap callback
              // 함수역할: 인식된 모든 약의 수정 가능한 가로 스크롤 표에서 캡처된 작업 `onEditRequested(scheduleIndex, schedule, _MedicationScheduleEditField.dosage)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              : () => onEditRequested(
                  scheduleIndex,
                  schedule,
                  _MedicationScheduleEditField.dosage,
                ),
          child: _TableValueText(
            value: schedule.dosageLabelForLanguage(previewText.language),
            scale: scale,
            isVerified: isVerified,
          ),
        ),
        _EditableMedicationCell(
          cellKey: Key('ocr-table-cell-$scheduleIndex-frequency'),
          semanticsLabel: previewText.editCell(
            previewText.dailyFrequency,
            schedule.dailyFrequencyLabelForLanguage(previewText.language),
          ),
          onTap: isVerified
              ? null
              // 함수이름: _buildMedicationRow.onTap callback
              // 함수역할: 인식된 모든 약의 수정 가능한 가로 스크롤 표에서 캡처된 작업 `onEditRequested(scheduleIndex, schedule, _MedicationScheduleEditField.dailyFrequency)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              : () => onEditRequested(
                  scheduleIndex,
                  schedule,
                  _MedicationScheduleEditField.dailyFrequency,
                ),
          child: _TableValueText(
            value: schedule.dailyFrequencyLabelForLanguage(
              previewText.language,
            ),
            scale: scale,
            isVerified: isVerified,
          ),
        ),
        _EditableMedicationCell(
          cellKey: Key('ocr-table-cell-$scheduleIndex-days'),
          semanticsLabel: previewText.editCell(
            previewText.totalDays,
            schedule.durationLabelForLanguage(previewText.language),
          ),
          onTap: isVerified
              ? null
              // 함수이름: _buildMedicationRow.onTap callback
              // 함수역할: 인식된 모든 약의 수정 가능한 가로 스크롤 표에서 캡처된 작업 `onEditRequested(scheduleIndex, schedule, _MedicationScheduleEditField.totalDays)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              : () => onEditRequested(
                  scheduleIndex,
                  schedule,
                  _MedicationScheduleEditField.totalDays,
                ),
          child: _TableValueText(
            value: schedule.durationLabelForLanguage(previewText.language),
            scale: scale,
            isVerified: isVerified,
          ),
        ),
        _EditableMedicationCell(
          cellKey: Key('ocr-table-cell-$scheduleIndex-date'),
          semanticsLabel: previewText.editCell(
            previewText.medicationStartDate,
            previewText.dateValue(schedule.prescriptionDate),
          ),
          onTap: isVerified
              ? null
              // 함수이름: _buildMedicationRow.onTap callback
              // 함수역할: 인식된 모든 약의 수정 가능한 가로 스크롤 표에서 캡처된 작업 `onEditRequested(scheduleIndex, schedule, _MedicationScheduleEditField.prescriptionDate)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              : () => onEditRequested(
                  scheduleIndex,
                  schedule,
                  _MedicationScheduleEditField.prescriptionDate,
                ),
          child: _TableValueText(
            value: previewText.dateValue(schedule.prescriptionDate),
            scale: scale,
            isVerified: isVerified,
          ),
        ),
        _EditableMedicationCell(
          cellKey: Key('ocr-table-cell-$scheduleIndex-slots'),
          semanticsLabel: previewText.editCell(
            previewText.scheduleSlots,
            previewText.slotSummary(schedule.slotKeys),
          ),
          onTap: isVerified
              ? null
              // 함수이름: _buildMedicationRow.onTap callback
              // 함수역할: 인식된 모든 약의 수정 가능한 가로 스크롤 표에서 캡처된 작업 `onEditRequested(scheduleIndex, schedule, _MedicationScheduleEditField.scheduleSlots)`을 실행한다.
              // 매개변수:
              // - 없음.
              // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
              : () => onEditRequested(
                  scheduleIndex,
                  schedule,
                  _MedicationScheduleEditField.scheduleSlots,
                ),
          child: _TableValueText(
            value: previewText.slotSummary(schedule.slotKeys),
            scale: scale,
            isVerified: isVerified,
          ),
        ),
      ],
    );
  }
}

// 클래스명: _TableHeaderCell
// 역할: 복약 표 열 이름의 공통 표시를 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 복약 표 열 이름의 공통 표시 위젯을 구성한다.
// 속성:
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
class _TableHeaderCell extends StatelessWidget {
  final String label;
  final double scale;

  // 함수이름: _TableHeaderCell
  // 함수역할: 복약 표 열 이름의 공통 표시에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // 반환값: 입력 설정이 반영된 _TableHeaderCell 인스턴스.
  const _TableHeaderCell({required this.label, required this.scale});

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 복약 표 열 이름의 공통 표시 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 복약 표 열 이름의 공통 표시에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        label,
        maxLines: 2,
        style: TextStyle(
          color: MedBuddyColors.textStrong,
          fontSize: 13 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// 클래스명: _EditableMedicationCell
// 역할: 접근성 버튼으로 작동하는 복약 값 셀을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 접근성 버튼으로 작동하는 복약 값 셀 위젯을 구성한다.
// 속성:
// - cellKey (Key): 위젯을 구분하고 상태를 유지할 식별 키.
// - semanticsLabel (String): 스크린 리더가 읽을 콘텐츠 또는 이미지 설명.
// - onTap (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
// - child (Widget): 해당 레이아웃 안에 배치할 콘텐츠 위젯.
class _EditableMedicationCell extends StatelessWidget {
  final Key cellKey;
  final String semanticsLabel;
  final VoidCallback? onTap;
  final Widget child;

  // 함수이름: _EditableMedicationCell
  // 함수역할: 접근성 버튼으로 작동하는 복약 값 셀에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - cellKey (Key): 위젯을 구분하고 상태를 유지할 식별 키.
  // - semanticsLabel (String): 스크린 리더가 읽을 콘텐츠 또는 이미지 설명.
  // - onTap (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // - child (Widget): 해당 레이아웃 안에 배치할 콘텐츠 위젯.
  // 반환값: 입력 설정이 반영된 _EditableMedicationCell 인스턴스.
  const _EditableMedicationCell({
    required this.cellKey,
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 접근성 버튼으로 작동하는 복약 값 셀 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 접근성 버튼으로 작동하는 복약 값 셀에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: semanticsLabel,
      child: InkWell(
        key: cellKey,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: child,
        ),
      ),
    );
  }
}

// 클래스명: _TableValueText
// 역할: 검증 상태를 구분하는 복약 표 값을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 검증 상태를 구분하는 복약 표 값 위젯을 구성한다.
// 속성:
// - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
// - isVerified (bool): 현재 약품이나 일정이 확인된 값인지 여부.
class _TableValueText extends StatelessWidget {
  final String value;
  final double scale;
  final bool isVerified;

  // 함수이름: _TableValueText
  // 함수역할: 검증 상태를 구분하는 복약 표 값 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - isVerified (bool): 현재 약품이나 일정이 확인된 값인지 여부.
  // 반환값: 입력 설정이 반영된 _TableValueText 인스턴스.
  const _TableValueText({
    required this.value,
    required this.scale,
    this.isVerified = false,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 검증 상태를 구분하는 복약 표 값 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 검증 상태를 구분하는 복약 표 값에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: isVerified
            ? MedBuddyColors.textLight
            : MedBuddyColors.textStrong,
        fontSize: 14 * scale,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        decoration: isVerified ? TextDecoration.lineThrough : null,
      ),
    );
  }
}

// 클래스명: _MedicationNameTableValue
// 역할: 약품명·보정 표식·최초 OCR 약품명을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약품명·보정 표식·최초 OCR 약품명 위젯을 구성한다.
// 속성:
// - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
// - isVerified (bool): 현재 약품이나 일정이 확인된 값인지 여부.
class _MedicationNameTableValue extends StatelessWidget {
  final MedicationSchedule schedule;
  final _PreviewText previewText;
  final double scale;
  final bool isVerified;

  // 함수이름: _MedicationNameTableValue
  // 함수역할: 약품명·보정 표식·최초 OCR 약품명에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - previewText (_PreviewText): 해당 화면 구역의 언어별 표시 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - isVerified (bool): 현재 약품이나 일정이 확인된 값인지 여부.
  // 반환값: 입력 설정이 반영된 _MedicationNameTableValue 인스턴스.
  const _MedicationNameTableValue({
    required this.schedule,
    required this.previewText,
    required this.scale,
    this.isVerified = false,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약품명·보정 표식·최초 OCR 약품명 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약품명·보정 표식·최초 OCR 약품명에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final correctionBadge = isVerified
        ? _CorrectionBadge(label: previewText.verified, scale: scale)
        : schedule.isNameConfirmed
        ? _CorrectionBadge(label: previewText.confirmed, scale: scale)
        : schedule.hasNameCorrection
        ? _CorrectionBadge(label: previewText.corrected, scale: scale)
        : schedule.isNameReviewRequired
        ? _CorrectionBadge(
            label: previewText.reviewNeeded,
            scale: scale,
            isWarning: true,
          )
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                schedule.displayNameForLanguage(previewText.language),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isVerified
                      ? MedBuddyColors.textLight
                      : MedBuddyColors.textStrong,
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                  decoration: isVerified ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (correctionBadge != null) ...[
              const SizedBox(width: 6),
              correctionBadge,
            ],
          ],
        ),
        if (schedule.hasNameCorrection) ...[
          const SizedBox(height: 4),
          Text(
            previewText.correctedFrom(schedule.rawMedicationName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MedBuddyColors.textLight,
              fontSize: 11 * scale,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ],
    );
  }
}

// 클래스명: _CorrectionBadge
// 역할: 약명 보정 또는 확인 필요 표식을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약명 보정 또는 확인 필요 표식 위젯을 구성한다.
// 속성:
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
// - isWarning (bool): 경고 색상과 강조를 사용할지 여부.
class _CorrectionBadge extends StatelessWidget {
  final String label;
  final double scale;
  final bool isWarning;

  // 함수이름: _CorrectionBadge
  // 함수역할: 약명 보정 또는 확인 필요 표식에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - scale (double): 사용자 접근성 설정을 반영한 콘텐츠 글씨 배율.
  // - isWarning (bool): 경고 색상과 강조를 사용할지 여부.
  // 반환값: 입력 설정이 반영된 _CorrectionBadge 인스턴스.
  const _CorrectionBadge({
    required this.label,
    required this.scale,
    this.isWarning = false,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약명 보정 또는 확인 필요 표식 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약명 보정 또는 확인 필요 표식에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isWarning ? const Color(0xFFFFF4D6) : const Color(0xFFE6F7F1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isWarning
              ? const Color(0xFF9A6700)
              : MedBuddyColors.primaryDark,
          fontSize: 10 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// 클래스명: _MedicationScheduleEditDialog
// 역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집을 담당한다.
// 주요 책임:
// - 약명, 조제일자, 투약량, 횟수, 투약일의 현재 값을 입력란에 표시한다.
// - 실제 복약할 아침·점심·저녁·취침 전 시간대를 사용자가 확인하게 한다.
// - 입력 형식을 검증한 뒤 변경된 복약 일정 객체를 반환한다.
// 속성:
// - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
// - initialField (_MedicationScheduleEditField): 편집 창에서 선택할 복약 정보 입력 항목.
// - isNewSchedule (bool): 기존 일정 수정이 아니라 새 약품 추가인지 여부.
class _MedicationScheduleEditDialog extends StatefulWidget {
  final MedicationSchedule medicationSchedule;
  final _PreviewText previewText;
  final UserSetting userSetting;
  final _MedicationScheduleEditField initialField;
  final bool isNewSchedule;

  // 함수이름: _MedicationScheduleEditDialog
  // 함수역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - previewText (_PreviewText): 해당 화면 구역의 언어별 표시 문구.
  // - userSetting (UserSetting): 언어·접근성·복약 알림 표시와 저장에 사용할 사용자 설정.
  // - initialField (_MedicationScheduleEditField): 편집 창에서 선택할 복약 정보 입력 항목.
  // - isNewSchedule (bool): 기존 일정 수정이 아니라 새 약품 추가인지 여부.
  // 반환값: 입력 설정이 반영된 _MedicationScheduleEditDialog 인스턴스.
  const _MedicationScheduleEditDialog({
    required this.medicationSchedule,
    required this.previewText,
    required this.userSetting,
    required this.initialField,
    this.isNewSchedule = false,
  });

  // 함수이름: createState
  // 함수역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집의 입력·표시 상태를 관리할 State 객체를 만든다.
  // 매개변수:
  // - 없음.
  // 반환값: 새 _MedicationScheduleEditDialogState 인스턴스.
  @override
  State<_MedicationScheduleEditDialog> createState() =>
      _MedicationScheduleEditDialogState();
}

// 클래스명: _MedicationScheduleEditDialogState
// 역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집의 화면 상태를 관리한다.
// 주요 책임:
// - 입력 컨트롤러를 생성하고 화면이 닫힐 때 안전하게 정리한다.
// - 유효한 입력만 MedicationSchedule로 변환해 호출 화면에 반환한다.
class _MedicationScheduleEditDialogState
    extends State<_MedicationScheduleEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _dosageController;
  late final TextEditingController _frequencyController;
  late final TextEditingController _daysController;
  late final TextEditingController _prescriptionDateController;
  late Set<String> _selectedSlotKeys;
  bool _showSlotValidationError = false;
  bool _restoreOriginalName = false;

  // 함수이름: initState
  // 함수역할: OCR 약명·용량·횟수·일수·날짜와 시간대 선택을 편집용 입력 상태로 복사한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.medicationSchedule.medicationName,
    );
    _dosageController = TextEditingController(
      text: widget.medicationSchedule.dosage,
    );
    _frequencyController = TextEditingController(
      text: widget.medicationSchedule.intakeTime,
    );
    _daysController = TextEditingController(
      text: widget.medicationSchedule.medicationTime <= 0
          ? ''
          : widget.medicationSchedule.medicationTime.toString(),
    );
    _prescriptionDateController = TextEditingController(
      text: _formatDate(
        widget.medicationSchedule.prescriptionDate ?? DateTime.now(),
      ),
    );
    _selectedSlotKeys = widget.medicationSchedule.slotKeys.toSet();
  }

  // 함수이름: dispose
  // 함수역할: _nameController, _dosageController, _frequencyController, _daysController, _prescriptionDateController 관련 자원을 정리하고 화면 수명 종료 처리를 수행한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _frequencyController.dispose();
    _daysController.dispose();
    _prescriptionDateController.dispose();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 OCR 약명·조제일·용량·횟수·일수·시간대 편집 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: OCR 약명·조제일·용량·횟수·일수·시간대 편집에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final text = widget.previewText;
    final scale = widget.userSetting.contentTextScale;

    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.isNewSchedule ? text.addTitle : text.editTitle,
        style: TextStyle(
          color: MedBuddyColors.textStrong,
          fontSize: 21 * scale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('ocr-edit-name'),
                controller: _nameController,
                autofocus:
                    widget.initialField ==
                    _MedicationScheduleEditField.medicationName,
                maxLength: 200,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.medicationName),
                // 함수이름: build.validator callback
                // 함수역할: 입력값을 `value == null || value.trim().isEmpty ? text.medicationNameRequired : null` 조건으로 검증한다.
                // 매개변수:
                // - value (콜백 계약에서 추론): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
                // 반환값: 유효하지 않으면 검증 문구, 유효하면 null.
                validator: (value) => value == null || value.trim().isEmpty
                    ? text.medicationNameRequired
                    : null,
              ),
              if (_hasRestorableOriginalName)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('ocr-restore-original-name'),
                    onPressed: _restoreOriginalMedicationName,
                    icon: const Icon(Icons.restore_rounded),
                    label: Text(text.restoreOriginalName),
                  ),
                ),
              TextFormField(
                key: const Key('ocr-edit-prescription-date'),
                controller: _prescriptionDateController,
                autofocus:
                    widget.initialField ==
                    _MedicationScheduleEditField.prescriptionDate,
                keyboardType: TextInputType.datetime,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                  LengthLimitingTextInputFormatter(10),
                ],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: text.prescriptionDate,
                  hintText: 'YYYY-MM-DD',
                  suffixIcon: IconButton(
                    tooltip: text.chooseDate,
                    onPressed: _selectPrescriptionDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                  ),
                ),
                validator: _validatePrescriptionDate,
              ),
              TextFormField(
                key: const Key('ocr-edit-dosage'),
                controller: _dosageController,
                autofocus:
                    widget.initialField == _MedicationScheduleEditField.dosage,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.dosage),
              ),
              TextFormField(
                key: const Key('ocr-edit-frequency'),
                controller: _frequencyController,
                autofocus:
                    widget.initialField ==
                    _MedicationScheduleEditField.dailyFrequency,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.dailyFrequency),
              ),
              TextFormField(
                key: const Key('ocr-edit-days'),
                controller: _daysController,
                autofocus:
                    widget.initialField ==
                    _MedicationScheduleEditField.totalDays,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: text.totalDays),
                validator: _validateMedicationDays,
                // 함수이름: build.onFieldSubmitted callback
                // 함수역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집에서 캡처된 작업 `_submit()`을 실행한다.
                // 매개변수:
                // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  text.scheduleSlots,
                  style: TextStyle(
                    color: MedBuddyColors.textStrong,
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Focus(
                autofocus:
                    widget.initialField ==
                    _MedicationScheduleEditField.scheduleSlots,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final slotKey in medicationScheduleSlotKeys)
                      FilterChip(
                        key: Key('ocr-edit-slot-$slotKey'),
                        label: Text(text.slotLabel(slotKey)),
                        selected: _selectedSlotKeys.contains(slotKey),
                        // 함수이름: build.onSelected callback
                        // 함수역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집에서 캡처된 작업 `setState(() {if (selected) {_selectedSlotKeys.add(slotKey);} else {_selectedSlotKeys.remove(slotKey);} _showSlotValidationError = false;})`을 실행한다.
                        // 매개변수:
                        // - selected (콜백 계약에서 추론): 현재 선택 집합에 포함되는지 여부.
                        // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                        onSelected: (selected) {
                          // 함수이름: build.setState callback
                          // 함수역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집의 입력·요청 상태를 `_showSlotValidationError = false`로 갱신한다.
                          // 매개변수:
                          // - 없음.
                          // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
                          setState(() {
                            if (selected) {
                              _selectedSlotKeys.add(slotKey);
                            } else {
                              _selectedSlotKeys.remove(slotKey);
                            }
                            _showSlotValidationError = false;
                          });
                        },
                      ),
                  ],
                ),
              ),
              if (_showSlotValidationError) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text.scheduleSlotRequired,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12 * scale,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('ocr-edit-cancel'),
          // 함수이름: build.onPressed callback
          // 함수역할: `Navigator.pop(context)`에 지정한 선택값 또는 취소 결과로 현재 화면을 닫는다.
          // 매개변수:
          // - 없음.
          // 반환값: 콜백 결과는 없으며 선택값은 화면 종료 결과로 전달한다.
          onPressed: () => Navigator.pop(context),
          child: Text(text.cancel),
        ),
        FilledButton(
          key: const Key('ocr-edit-save'),
          onPressed: _submit,
          child: Text(text.apply),
        ),
      ],
    );
  }

  // 함수이름: _validateMedicationDays
  // 함수역할: 총 투약일 입력값이 비어 있거나 허용 범위의 양의 정수인지 확인한다.
  // 매개변수:
  // - value (String?): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 검증·상태 안내 문구. 안내가 필요하지 않으면 null.
  String? _validateMedicationDays(String? value) {
    final trimmedValue = value?.trim() ?? '';
    if (trimmedValue.isEmpty) {
      return null;
    }
    final medicationDays = int.tryParse(trimmedValue);
    if (medicationDays == null ||
        medicationDays <= 0 ||
        medicationDays > 3650) {
      return widget.previewText.invalidTotalDays;
    }
    return null;
  }

  // 함수이름: _validatePrescriptionDate
  // 함수역할: 조제일자가 실제 달력에 존재하고 허용 범위 안의 날짜인지 확인한다.
  // 매개변수:
  // - value (String?): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 검증·상태 안내 문구. 안내가 필요하지 않으면 null.
  String? _validatePrescriptionDate(String? value) {
    final parsedDate = _parseDate(value?.trim() ?? '');
    if (parsedDate == null) {
      return widget.previewText.invalidPrescriptionDate;
    }
    if (parsedDate.isBefore(_minimumPrescriptionDate) ||
        parsedDate.isAfter(_maximumPrescriptionDate)) {
      return widget.previewText.prescriptionDateOutOfRange;
    }
    return null;
  }

  // 함수이름: _minimumPrescriptionDate
  // 함수역할: 허용할 가장 이른 처방일인 2000년 1월 1일을 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: DateTime: 허용 범위 또는 시각 제거 규칙을 반영한 날짜.
  DateTime get _minimumPrescriptionDate => DateTime(2000);

  // 함수이름: _maximumPrescriptionDate
  // 함수역할: 현재 날짜에서 365일 뒤의 자정을 가장 늦은 처방일로 계산한다.
  // 매개변수:
  // - 없음.
  // 반환값: DateTime: 허용 범위 또는 시각 제거 규칙을 반영한 날짜.
  DateTime get _maximumPrescriptionDate {
    final maximumDate = DateTime.now().add(const Duration(days: 365));
    return DateTime(maximumDate.year, maximumDate.month, maximumDate.day);
  }

  // 함수이름: _selectPrescriptionDate
  // 함수역할: 달력에서 조제일자를 선택하고 직접 입력 필드에 반영한다.
  // 매개변수:
  // - 없음.
  // 반환값: 요청한 상호작용 또는 갱신 처리가 끝나면 완료되는 Future<void>.
  Future<void> _selectPrescriptionDate() async {
    final parsedInitialDate =
        _parseDate(_prescriptionDateController.text.trim()) ?? DateTime.now();
    final initialDate = parsedInitialDate.isBefore(_minimumPrescriptionDate)
        ? _minimumPrescriptionDate
        : parsedInitialDate.isAfter(_maximumPrescriptionDate)
        ? _maximumPrescriptionDate
        : parsedInitialDate;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: _minimumPrescriptionDate,
      lastDate: _maximumPrescriptionDate,
    );
    if (!mounted || selectedDate == null) {
      return;
    }
    // 함수이름: _selectPrescriptionDate.setState callback
    // 함수역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집의 입력·요청 상태를 `_prescriptionDateController.text = _formatDate(selectedDate)`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _prescriptionDateController.text = _formatDate(selectedDate);
    });
  }

  // 함수이름: _submit
  // 함수역할: 수정 입력값을 검증하고 변경된 복약 일정 객체를 호출 화면으로 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _submit() {
    final hasSelectedSlot = _selectedSlotKeys.isNotEmpty;
    if (!hasSelectedSlot) {
      // 함수이름: _submit.setState callback
      // 함수역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집의 입력·요청 상태를 `_showSlotValidationError = true`로 갱신한다.
      // 매개변수:
      // - 없음.
      // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
      setState(() => _showSlotValidationError = true);
    }
    if (!(_formKey.currentState?.validate() ?? false) || !hasSelectedSlot) {
      return;
    }

    final medicationName = _nameController.text.trim();
    final originalMedicationName = widget.medicationSchedule.rawMedicationName
        .trim();
    final restoresOriginalName =
        _restoreOriginalName && medicationName == originalMedicationName;

    Navigator.pop(
      context,
      widget.medicationSchedule.copyWith(
        medicationName: medicationName,
        dosage: _dosageController.text.trim(),
        intakeTime: _frequencyController.text.trim(),
        medicationTime: int.tryParse(_daysController.text.trim()) ?? 0,
        prescriptionDate: _parseDate(_prescriptionDateController.text.trim()),
        scheduleSlotKeys: medicationScheduleSlotKeys
            .where(_selectedSlotKeys.contains)
            .toList(growable: false),
        rawMedicationName: widget.isNewSchedule || restoresOriginalName
            ? ''
            : widget.medicationSchedule.rawMedicationName,
        nameConfidence: widget.isNewSchedule
            ? 1
            : restoresOriginalName
            ? 0
            : 1,
        nameCorrectionSource: widget.isNewSchedule
            ? 'manual_add'
            : restoresOriginalName
            ? 'ocr_reset'
            : 'user_review',
      ),
    );
  }

  // 함수이름: _hasRestorableOriginalName
  // 함수역할: 최초 OCR 약명이 비어 있지 않고 현재 약명과 다른지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get _hasRestorableOriginalName {
    final originalName = widget.medicationSchedule.rawMedicationName.trim();
    return originalName.isNotEmpty &&
        originalName != widget.medicationSchedule.medicationName.trim();
  }

  // 함수이름: _restoreOriginalMedicationName
  // 함수역할: 자동 보정 또는 사용자 수정 전의 최초 OCR 약명으로 입력값을 되돌린다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _restoreOriginalMedicationName() {
    // 함수이름: _restoreOriginalMedicationName.setState callback
    // 함수역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집의 입력·요청 상태를 `_nameController.text = widget.medicationSchedule.rawMedicationName.trim(); _nameController.selection = TextSelection.collapsed(offset: _nameController.text.length); _restoreOriginalName = true`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _nameController.text = widget.medicationSchedule.rawMedicationName.trim();
      _nameController.selection = TextSelection.collapsed(
        offset: _nameController.text.length,
      );
      _restoreOriginalName = true;
    });
  }

  // 함수이름: _parseDate
  // 함수역할: 연-월-일 형식과 실제 존재하는 달력 날짜를 검증하고 잘못된 날짜는 null로 처리한다.
  // 매개변수:
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: DateTime?: 유효한 달력 날짜; 형식·날짜가 잘못되면 null.
  DateTime? _parseDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsedDate = DateTime(year, month, day);
    if (parsedDate.year != year ||
        parsedDate.month != month ||
        parsedDate.day != day) {
      return null;
    }
    return parsedDate;
  }

  // 함수이름: _formatDate
  // 함수역할: 날짜를 네 자리 연도와 두 자리 월·일의 연-월-일 형식으로 표시한다.
  // 매개변수:
  // - value (DateTime): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

// 클래스명: _PreviewText
// 역할: OCR 복약 정보 표와 약명·일정 수정 대화상자에 쓰는 한국어·영어 문구를 담당한다.
// 주요 책임:
// - OCR 복약 정보 표와 약명·일정 수정 대화상자에 쓰는 한국어·영어 문구의 언어를 선택하고 안내에 필요한 값을 문구에 반영한다.
// 속성:
// - language (String): 화면 문구를 선택할 언어 코드.
class _PreviewText {
  final String language;

  // 함수이름: _PreviewText
  // 함수역할: OCR 복약 정보 표와 약명·일정 수정 대화상자에 쓰는 한국어·영어 문구 선택에 사용할 언어를 보관한다.
  // 매개변수:
  // - language (String): 화면 문구를 선택할 언어 코드.
  // 반환값: 입력 설정이 반영된 _PreviewText 인스턴스.
  const _PreviewText(this.language);

  // 함수이름: isEnglish
  // 함수역할: 언어 코드가 en과 정확히 일치하는지 확인한다.
  // 매개변수:
  // - 없음.
  // 반환값: 설명한 조건을 만족하면 true, 아니면 false.
  bool get isEnglish => language == 'en';

  // 함수이름: back
  // 함수역할: 현재 언어와 입력값에 맞춰 "뒤로가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get back => isEnglish ? 'Back' : '뒤로가기';
  // 함수이름: analyze
  // 함수역할: 현재 언어와 입력값에 맞춰 "분석하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get analyze => isEnglish ? 'Analyze' : '분석하기';
  // 함수이름: reviewBeforeAnalyze
  // 함수역할: 현재 언어와 입력값에 맞춰 "검토 후 분석하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get reviewBeforeAnalyze =>
      isEnglish ? 'Review and analyze' : '검토 후 분석하기';
  // 함수이름: confirmAndAnalyze
  // 함수역할: 현재 언어와 입력값에 맞춰 "검토 완료 및 분석하기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get confirmAndAnalyze =>
      isEnglish ? 'Confirm and analyze' : '검토 완료 및 분석하기';
  // 함수이름: noInformation
  // 함수역할: 현재 언어와 입력값에 맞춰 "정보 없음" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get noInformation => isEnglish ? 'No info' : '정보 없음';
  // 함수이름: corrected
  // 함수역할: 현재 언어와 입력값에 맞춰 "Corrected" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get corrected => isEnglish ? 'Corrected' : '보정';
  // 함수이름: confirmed
  // 함수역할: 현재 언어와 입력값에 맞춰 "확인 완료" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get confirmed => isEnglish ? 'Confirmed' : '확인 완료';
  // 함수이름: reviewNeeded
  // 함수역할: 현재 언어와 입력값에 맞춰 "검토 필요" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get reviewNeeded => isEnglish ? 'Review' : '검토 필요';
  // 함수이름: verified
  // 함수역할: 현재 언어와 입력값에 맞춰 "확인됨" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get verified => isEnglish ? 'Verified' : '확인됨';
  // 함수이름: edit
  // 함수역할: 현재 언어와 입력값에 맞춰 "OCR 인식 결과 수정" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get edit => isEnglish ? 'Edit OCR result' : 'OCR 인식 결과 수정';
  // 함수이름: editTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "OCR 인식 결과 수정" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get editTitle => isEnglish ? 'Edit OCR result' : 'OCR 인식 결과 수정';
  // 함수이름: addTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "누락된 약 추가" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get addTitle => isEnglish ? 'Add missing medication' : '누락된 약 추가';
  // 함수이름: addMissingMedication
  // 함수역할: 현재 언어와 입력값에 맞춰 "누락된 약 추가" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get addMissingMedication =>
      isEnglish ? 'Add missing medication' : '누락된 약 추가';
  // 함수이름: retryUnverifiedMedications
  // 함수역할: 현재 언어와 입력값에 맞춰 "미확인 약 다시 조회" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get retryUnverifiedMedications =>
      isEnglish ? 'Retry unverified medications' : '미확인 약 다시 조회';
  // 함수이름: continueWithVerifiedOnly
  // 함수역할: 현재 언어와 입력값에 맞춰 "확인된 약만으로 계속" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get continueWithVerifiedOnly =>
      isEnglish ? 'Continue with verified medications only' : '확인된 약만으로 계속';
  // 함수이름: continueWithVerifiedTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "미확인 약을 제외할까요?" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get continueWithVerifiedTitle =>
      isEnglish ? 'Exclude unverified medications?' : '미확인 약을 제외할까요?';
  // 함수이름: continueWithVerifiedWarning
  // 함수역할: 현재 언어와 입력값에 맞춰 "미확인 약 $count개는 분석 결과와 복약 일정에 포함되지 않습니다. 취소한 뒤 약명을 수정해 다시 조회할 수 있습니다." 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String continueWithVerifiedWarning(int count) => isEnglish
      ? '$count unverified medication item(s) will not appear in the result or schedule. You can cancel and correct them instead.'
      : '미확인 약 $count개는 분석 결과와 복약 일정에 포함되지 않습니다. 취소한 뒤 약명을 수정해 다시 조회할 수 있습니다.';
  // 함수이름: continueLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "Continue" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get continueLabel => isEnglish ? 'Continue' : '계속';
  // 함수이름: medicationName
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 이름" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationName => isEnglish ? 'Medication name' : '약 이름';
  // 함수이름: dosage
  // 함수역할: 현재 언어와 입력값에 맞춰 "1회 투약량" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get dosage => isEnglish ? 'Dose per intake' : '1회 투약량';
  // 함수이름: dailyFrequency
  // 함수역할: 현재 언어와 입력값에 맞춰 "1일 횟수" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get dailyFrequency => isEnglish ? 'Daily frequency' : '1일 횟수';
  // 함수이름: totalDays
  // 함수역할: 현재 언어와 입력값에 맞춰 "총 투약일" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get totalDays => isEnglish ? 'Total days' : '총 투약일';
  // 함수이름: cancel
  // 함수역할: 현재 언어와 입력값에 맞춰 "Cancel" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get cancel => isEnglish ? 'Cancel' : '취소';
  // 함수이름: apply
  // 함수역할: 현재 언어와 입력값에 맞춰 "Apply" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get apply => isEnglish ? 'Apply' : '적용';
  // 함수이름: restoreOriginalName
  // 함수역할: 현재 언어와 입력값에 맞춰 "최초 인식 약명으로 되돌리기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get restoreOriginalName =>
      isEnglish ? 'Restore the original OCR name' : '최초 인식 약명으로 되돌리기';
  // 함수이름: medicationNameRequired
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 이름을 입력해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationNameRequired =>
      isEnglish ? 'Enter a medication name.' : '약 이름을 입력해주세요.';
  // 함수이름: prescriptionDate
  // 함수역할: 현재 언어와 입력값에 맞춰 "조제일자" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get prescriptionDate => isEnglish ? 'Dispensing date' : '조제일자';
  // 함수이름: chooseDate
  // 함수역할: 현재 언어와 입력값에 맞춰 "날짜 선택" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get chooseDate => isEnglish ? 'Choose date' : '날짜 선택';
  // 함수이름: invalidPrescriptionDate
  // 함수역할: 현재 언어와 입력값에 맞춰 "올바른 날짜를 YYYY-MM-DD 형식으로 입력해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get invalidPrescriptionDate => isEnglish
      ? 'Enter a valid date as YYYY-MM-DD.'
      : '올바른 날짜를 YYYY-MM-DD 형식으로 입력해주세요.';
  // 함수이름: prescriptionDateOutOfRange
  // 함수역할: 현재 언어와 입력값에 맞춰 "2000-01-01부터 오늘 기준 1년 이내 날짜를 입력해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get prescriptionDateOutOfRange => isEnglish
      ? 'Enter a date from 2000-01-01 through one year from today.'
      : '2000-01-01부터 오늘 기준 1년 이내 날짜를 입력해주세요.';
  // 함수이름: scheduleSlots
  // 함수역할: 현재 언어와 입력값에 맞춰 "실제 복약 시간대" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get scheduleSlots => isEnglish ? 'Medication times' : '실제 복약 시간대';
  // 함수이름: scheduleSlotRequired
  // 함수역할: 현재 언어와 입력값에 맞춰 "복약 시간대를 하나 이상 선택해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get scheduleSlotRequired => isEnglish
      ? 'Select at least one medication time.'
      : '복약 시간대를 하나 이상 선택해주세요.';
  // 함수이름: invalidTotalDays
  // 함수역할: 현재 언어와 입력값에 맞춰 "1일 이상 3650일 이하의 숫자를 입력해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get invalidTotalDays => isEnglish
      ? 'Enter a number between 1 and 3650.'
      : '1일 이상 3650일 이하의 숫자를 입력해주세요.';
  // 함수이름: medicationStartDate
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 시작일" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationStartDate => isEnglish ? 'Start date' : '복용 시작일';
  // 함수이름: tableEditGuide
  // 함수역할: 현재 언어와 입력값에 맞춰 "표를 옆으로 밀어 더 확인하고, 수정할 값은 바로 눌러주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get tableEditGuide => isEnglish
      ? 'Swipe sideways to see more. Tap any value to edit it.'
      : '표를 옆으로 밀어 더 확인하고, 수정할 값은 바로 눌러주세요.';
  // 함수이름: tableScrollHint
  // 함수역할: 현재 언어와 입력값에 맞춰 "표를 옆으로 밀어 모든 복약 정보를 확인해보세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get tableScrollHint => isEnglish
      ? 'Swipe sideways to review all medication details.'
      : '표를 옆으로 밀어 모든 복약 정보를 확인해보세요.';

  // 함수이름: lookupReviewGuide
  // 함수역할: 현재 언어와 입력값에 맞춰 "약 $count개를 공공데이터에서 확인하지 못했습니다. 확인된 행은 취소선으로 잠겨 있습니다. 나머지 약명을 수정한 뒤 다시 조회해주세요." 문구를 제공한다.
  // 매개변수:
  // - count (int): 문구나 목록에 표시할 항목 수 또는 일련번호.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String lookupReviewGuide(int count) => isEnglish
      ? '$count medication item(s) could not be matched. Verified rows are crossed out and locked. Correct the remaining rows, then retry.'
      : '약 $count개를 공공데이터에서 확인하지 못했습니다. 확인된 행은 취소선으로 잠겨 있습니다. 나머지 약명을 수정한 뒤 다시 조회해주세요.';

  // 함수이름: slotLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "취침 전" 문구를 제공한다.
  // 매개변수:
  // - slotKey (String): 아침·점심·저녁·취침 전을 구분하는 시간대 키.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String slotLabel(String slotKey) {
    if (isEnglish) {
      return switch (slotKey) {
        'morning' => 'Morning',
        'lunch' => 'Lunch',
        'evening' => 'Evening',
        'bedtime' => 'Bedtime',
        _ => slotKey,
      };
    }
    return switch (slotKey) {
      'morning' => '아침',
      'lunch' => '점심',
      'evening' => '저녁',
      'bedtime' => '취침 전',
      _ => slotKey,
    };
  }

  // 함수이름: recognizedRegionGuide
  // 함수역할: 현재 언어와 입력값에 맞춰 "초록색은 약품 정보 인식 영역이며 회색은 개인정보 마스킹 영역입니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get recognizedRegionGuide => isEnglish
      ? 'Green boxes show medication information. Gray areas mask personal data.'
      : '초록색은 약품 정보 인식 영역이며 회색은 개인정보 마스킹 영역입니다.';
  // 함수이름: imageUnavailable
  // 함수역할: 현재 언어와 입력값에 맞춰 "이미지를 표시할 수 없습니다." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get imageUnavailable =>
      isEnglish ? 'Image preview unavailable' : '이미지를 표시할 수 없습니다.';
  // 함수이름: regionUnavailable
  // 함수역할: 현재 언어와 입력값에 맞춰 "인식 위치 정보가 없어 아래 추출 목록을 확인해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get regionUnavailable => isEnglish
      ? 'Region coordinates are unavailable. Review the list below.'
      : '인식 위치 정보가 없어 아래 추출 목록을 확인해주세요.';
  // 함수이름: privacyNotice
  // 함수역할: 현재 언어와 입력값에 맞춰 "원본 이미지는 이 기기에만 남습니다. 기기에서 OCR한 뒤 감지된 개인정보를 제거한" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get privacyNotice => isEnglish
      ? 'The original image stays on this device. Only OCR text with detected '
            'personal identifiers removed is sent for medication analysis.'
      : '원본 이미지는 이 기기에만 남습니다. 기기에서 OCR한 뒤 감지된 개인정보를 제거한 '
            '복약 관련 텍스트만 분석 서버로 전송합니다.';
  // 함수이름: sensitiveMaskLabel
  // 함수역할: 현재 언어와 입력값에 맞춰 "개인정보 마스킹" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get sensitiveMaskLabel =>
      isEnglish ? 'Personal information masked' : '개인정보 마스킹';
  // 함수이름: openImagePreview
  // 함수역할: 현재 언어와 입력값에 맞춰 "이미지 크게 보기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get openImagePreview => isEnglish ? 'Open image preview' : '이미지 크게 보기';
  // 함수이름: expandedImageTitle
  // 함수역할: 현재 언어와 입력값에 맞춰 "인식 영역 상세보기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get expandedImageTitle =>
      isEnglish ? 'Recognized image' : '인식 영역 상세보기';
  // 함수이름: close
  // 함수역할: 현재 언어와 입력값에 맞춰 "Close" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get close => isEnglish ? 'Close' : '닫기';

  // 함수이름: editCell
  // 함수역할: 현재 언어와 입력값에 맞춰 "$fieldLabel 수정. 현재 값: $value" 문구를 제공한다.
  // 매개변수:
  // - fieldLabel (String): 입력란·선택지·명령을 구분해 표시할 문구.
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String editCell(String fieldLabel, String value) {
    return isEnglish
        ? 'Edit $fieldLabel. Current value: $value'
        : '$fieldLabel 수정. 현재 값: $value';
  }

  // 함수이름: dateValue
  // 함수역할: 처방일을 연-월-일로 표시하고 값이 없으면 정보 없음 문구를 사용한다.
  // 매개변수:
  // - date (DateTime?): 표시·비교 기준이 되는 날짜 또는 이전·현재 값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String dateValue(DateTime? date) {
    if (date == null) {
      return noInformation;
    }
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // 함수이름: slotSummary
  // 함수역할: 시간대 키를 현재 언어의 이름으로 변환해 구분자로 묶는다.
  // 매개변수:
  // - slotKeys (List<String>): 약품에 적용할 복약 시간대 키 목록.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String slotSummary(List<String> slotKeys) {
    if (slotKeys.isEmpty) {
      return noInformation;
    }
    return slotKeys.map(slotLabel).join(', ');
  }

  // 함수이름: correctedFrom
  // 함수역할: 현재 언어와 입력값에 맞춰 "OCR 원문: $rawName" 문구를 제공한다.
  // 매개변수:
  // - rawName (String): 보정 전 최초 OCR 약품명.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String correctedFrom(String rawName) {
    return isEnglish ? 'OCR: $rawName' : 'OCR 원문: $rawName';
  }

  // 함수이름: title
  // 함수역할: 현재 언어와 입력값에 맞춰 "${date.month}/${date.day} ($weekday) 처방 내역" 문구를 제공한다.
  // 매개변수:
  // - date (DateTime): 표시·비교 기준이 되는 날짜 또는 이전·현재 값.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String title(DateTime date) {
    if (isEnglish) {
      return '${date.month}/${date.day} Prescription';
    }

    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[date.weekday - 1];
    return '${date.month}/${date.day} ($weekday) 처방 내역';
  }
}
