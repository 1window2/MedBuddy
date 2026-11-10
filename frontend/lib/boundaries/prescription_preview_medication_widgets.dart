part of 'prescription_analysis_preview_ui_boundary.dart';

// 파일명: prescription_preview_medication_widgets.dart
// 역할: OCR 복약 정보 표와 약명·일정 수정 대화상자를 제공한다.

// 클래스명: _MedicationScheduleEditField
// 역할: OCR 표에서 선택한 편집 시작 항목.
// 주요 책임: 약명·용량·횟수·일수·날짜·시간대 중 초기 입력란을 지정한다.
// 속성: medicationName/dosage/dailyFrequency/totalDays/prescriptionDate/scheduleSlots: 입력 항목.
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

// 클래스명: _PreviewMedicationList
// 역할: 약별 인식 결과와 조회 후보 확인을 세로 카드로 표시한다.
// 주요 책임: 조회 상태를 행 순서에 맞춰 표시하고 항목별 편집·후보 확인을 부모에게 전달한다.
// 속성: medicationScheduleList (List<MedicationSchedule>): 일정; lookupStatuses (List<MedicationLookupStatus?>): 같은 순서 상태; matchReviews (Map<int,MedicationMatchReview>): 후보; verifiedScheduleIndexes (Set<int>): 확정; previewText: 문구; onEditRequested/onCandidateRequested: 편집 명령.
class _PreviewMedicationList extends StatelessWidget {
  final List<MedicationSchedule> medicationScheduleList;
  final _PreviewText previewText;
  final _MedicationTableEditCallback onEditRequested;
  final Set<int> verifiedScheduleIndexes;
  final bool isMedicationLookupReview;
  final Map<int, MedicationMatchReview> matchReviews;
  // 부모 화면이 행 순서대로 정한 조회 상태이며 조회 이력이 없는 행은 null이다.
  final List<MedicationLookupStatus?> lookupStatuses;
  final void Function(int, MedicationMatchReview)? onCandidateRequested;

  // 함수이름: _PreviewMedicationList
  // 함수역할: 행 순서가 일치하는 일정·조회 상태와 편집 및 후보 확인 콜백을 받는다.
  // 매개변수: medicationScheduleList (List<MedicationSchedule>): 일정; previewText (_PreviewText): 문구; onEditRequested (_MedicationTableEditCallback): 편집; verifiedScheduleIndexes (Set<int>): 확정; isMedicationLookupReview (bool): 검토 모드; matchReviews (Map<int,MedicationMatchReview>): 후보; lookupStatuses (List<MedicationLookupStatus?>): 행별 상태; onCandidateRequested (void Function(int,MedicationMatchReview)?): 확인.
  // 반환값: 새 _PreviewMedicationList.
  const _PreviewMedicationList({
    required this.medicationScheduleList,
    required this.previewText,
    required this.onEditRequested,
    required this.verifiedScheduleIndexes,
    required this.isMedicationLookupReview,
    required this.matchReviews,
    required this.lookupStatuses,
    required this.onCandidateRequested,
  });

  // 함수이름: build
  // 함수역할: 일정 순서대로 약품 카드를 세로 배치하고 카드 사이에만 간격을 둔다.
  // 매개변수: context (BuildContext): 카드 표시 위치.
  // 반환값: 약품 카드 Column.
  @override
  Widget build(BuildContext context) => Column(
    key: const Key('ocr-medication-list'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < medicationScheduleList.length; index++) ...[
        if (index > 0) const SizedBox(height: 12),
        _buildMedicationCard(context, index, medicationScheduleList[index]),
      ],
    ],
  );

  // Function Name: _buildMedicationCard
  // Description: Builds one medication review card with lookup status, editable schedule fields and candidate confirmation only when still unverified.
  // Parameters: context (BuildContext): layout; index (int): aligned schedule/status index; schedule (MedicationSchedule): OCR or edited schedule.
  // Returns: Review card for the supplied row.
  Widget _buildMedicationCard(
    BuildContext context,
    int index,
    MedicationSchedule schedule,
  ) {
    final verified = verifiedScheduleIndexes.contains(index);
    final review = matchReviews[index];
    final lookupStatus = lookupStatuses[index];
    final canReview =
        isMedicationLookupReview &&
        !verified &&
        review != null &&
        review.candidates.isNotEmpty &&
        onCandidateRequested != null;

    // 함수이름: field
    // 함수역할: 약별 필드에 제목·현재값·선택적 보조 표시를 붙이고 해당 편집 항목으로 연결한다.
    // 매개변수: suffix/label/value (String): 키 접미사·제목·값; editField (_MedicationScheduleEditField): 수정 항목; extra (Widget?): 보조 내용.
    // 반환값: 접근성 편집 문구를 포함한 _EditableMedicationCell.
    Widget field(
      String suffix,
      String label,
      String value,
      _MedicationScheduleEditField editField, {
      Widget? extra,
    }) => _EditableMedicationCell(
      cellKey: Key('ocr-table-cell-$index-$suffix'),
      semanticsLabel: previewText.editCell(label, value),
      onTap: () => onEditRequested(index, schedule, editField),
      alignment: Alignment.center,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MedBuddyColors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          _TableValueText(value: value),
          if (extra != null) ...[const SizedBox(height: 6), extra],
        ],
      ),
    );

    final fields = [
      field(
        'dosage',
        previewText.isEnglish ? 'Dose' : previewText.dosage,
        schedule.dosageLabelForLanguage(previewText.language),
        _MedicationScheduleEditField.dosage,
      ),
      field(
        'days',
        previewText.isEnglish ? 'Duration' : previewText.totalDays,
        schedule.durationLabelForLanguage(previewText.language),
        _MedicationScheduleEditField.totalDays,
      ),
      field(
        'date',
        previewText.medicationStartDate,
        previewText.dateValue(schedule.prescriptionDate),
        _MedicationScheduleEditField.prescriptionDate,
      ),
      field(
        'slots',
        previewText.scheduleSlots,
        schedule.slotSummaryLabelForLanguage(
          previewText.language,
          emptySlotsLabel: previewText.noInformation,
        ),
        _MedicationScheduleEditField.scheduleSlots,
        extra:
            !schedule.isAsNeeded &&
                (schedule.needsScheduleReview ||
                    !readDoseCycle(schedule.intakeTime).isDaily)
            ? Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (schedule.needsScheduleReview)
                    _CorrectionBadge(
                      key: Key('ocr-table-dosing-mode-$index'),
                      label: previewText.isEnglish
                          ? 'Schedule needs review'
                          : '복용 일정 확인 필요',
                      isWarning: true,
                    ),
                  if (!readDoseCycle(schedule.intakeTime).isDaily)
                    _CorrectionBadge(
                      key: Key('ocr-table-not-daily-$index'),
                      label: previewText.notDailyBadge,
                      isWarning: true,
                    ),
                ],
              )
            : null,
      ),
    ];
    return Material(
      key: Key('ocr-medication-card-$index'),
      color: lookupStatus == null
          ? Colors.white
          : _lookupStatusPresentation(lookupStatus, previewText.isEnglish).$3,
      shape: RoundedRectangleBorder(
        borderRadius: MedBuddyRadii.small,
        side: const BorderSide(color: MedBuddyColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpandableMedicationSection(
        initiallyExpanded: true,
        isEnglish: previewText.isEnglish,
        toggleKey: Key('ocr-medication-toggle-$index'),
        headerBuilder: (toggle) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MedicationNameTableValue(
              schedule: schedule,
              previewText: previewText,
              lookupStatus: lookupStatus,
              index: index,
              toggle: toggle,
              onEditRequested: () => onEditRequested(
                index,
                schedule,
                _MedicationScheduleEditField.medicationName,
              ),
            ),
            if (canReview)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: OutlinedButton.icon(
                  key: Key('medication-candidates-$index'),
                  onPressed: () => onCandidateRequested!(index, review),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    previewText.isEnglish ? 'Review candidates' : '약품 후보 확인',
                  ),
                ),
              ),
          ],
        ),
        details: Column(
          children: [
            const Divider(height: 1),
            // 행 높이는 내용에 맞추고 각 셀의 폭은 균등하게 유지한다.
            Table(
              key: Key('ocr-medication-summary-$index'),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: const TableBorder(
                verticalInside: BorderSide(color: MedBuddyColors.outline),
              ),
              children: [TableRow(children: fields.take(2).toList())],
            ),
            const Divider(height: 1),
            Table(
              key: Key('ocr-medication-schedule-$index'),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: const TableBorder(
                verticalInside: BorderSide(color: MedBuddyColors.outline),
              ),
              children: [TableRow(children: fields.skip(2).toList())],
            ),
          ],
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
  final AlignmentGeometry alignment;

  // 함수이름: _EditableMedicationCell
  // 함수역할: 접근성 버튼으로 작동하는 복약 값 셀에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - cellKey (Key): 위젯을 구분하고 상태를 유지할 식별 키.
  // - semanticsLabel (String): 스크린 리더가 읽을 콘텐츠 또는 이미지 설명.
  // - onTap (VoidCallback?): 해당 항목의 명시된 주 동작을 실행할 콜백.
  // - child (Widget): 해당 레이아웃 안에 배치할 콘텐츠 위젯.
  // - alignment (AlignmentGeometry): 셀 안에서 child를 배치할 정렬이며 기본값은 Alignment.centerLeft이다.
  // 반환값: 입력 설정이 반영된 _EditableMedicationCell 인스턴스.
  const _EditableMedicationCell({
    required this.cellKey,
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
    this.alignment = Alignment.centerLeft,
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
          constraints: const BoxConstraints(minHeight: 48),
          alignment: alignment,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: child,
        ),
      ),
    );
  }
}

// 클래스명: _TableValueText
// 역할: 복약 표 값을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값으로 복약 표 값 위젯을 구성한다.
// 속성:
// - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
class _TableValueText extends StatelessWidget {
  final String value;

  // 함수이름: _TableValueText
  // 함수역할: 복약 표에 표시할 값을 보관한다.
  // 매개변수:
  // - value (String): 검증·정규화·표시하거나 선택 콜백으로 전달할 입력값.
  // 반환값: 입력 설정이 반영된 _TableValueText 인스턴스.
  const _TableValueText({required this.value});

  // 함수이름: build
  // 함수역할: 현재 입력값을 반영해 복약 표 값 화면을 구성한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 복약 표 값에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: MedBuddyColors.textStrong,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}

// 클래스명: _MedicationNameTableValue
// 역할: 약품명·조회 상태·순번과 편집 표시를 담당한다.
// 주요 책임:
// - 약품명 오른쪽에 조회 상태와 순번을 표시하고 큰 글씨에서는 줄을 나눈다.
// 속성:
// - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
// - lookupStatus (MedicationLookupStatus?): 약별 조회 결과이며 조회 이력이 없으면 null.
// - index (int): 원래 처방 목록의 0부터 시작하는 위치.
class _MedicationNameTableValue extends StatelessWidget {
  final MedicationSchedule schedule;
  final _PreviewText previewText;
  final MedicationLookupStatus? lookupStatus;
  final int index;
  final Widget toggle;
  final VoidCallback onEditRequested;

  // 함수이름: _MedicationNameTableValue
  // 함수역할: 약품명·조회 상태·순번에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - schedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - previewText (_PreviewText): 해당 화면 구역의 언어별 표시 문구.
  // - lookupStatus (MedicationLookupStatus?): 약별 조회 결과.
  // - index (int): 원래 처방 목록의 위치.
  // - toggle (Widget): 상위 약품 구역의 복약 상세 접기·펼치기 버튼.
  // - onEditRequested (VoidCallback): 이 행의 약품명 수정 화면을 여는 콜백.
  // 반환값: 입력 설정이 반영된 _MedicationNameTableValue 인스턴스.
  const _MedicationNameTableValue({
    required this.schedule,
    required this.previewText,
    required this.lookupStatus,
    required this.index,
    required this.toggle,
    required this.onEditRequested,
  });

  // 함수이름: build
  // 함수역할: 현재 입력값과 상태를 반영해 약품명·조회 상태·순번을 배치한다.
  // 매개변수:
  // - context (BuildContext): 테마·접근성 설정·화면 이동을 참조할 위젯 트리 위치.
  // 반환값: 약품명·조회 상태·순번에 쓰는 위젯 트리.
  @override
  Widget build(BuildContext context) {
    final name = Text(
      schedule.displayNameForLanguage(previewText.language),
      key: Key('ocr-medication-name-$index'),
      style: const TextStyle(
        color: MedBuddyColors.textStrong,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );
    final status = lookupStatus;
    final badge = status == null
        ? null
        : _MedicationLookupBadge(
            key: Key('ocr-lookup-status-$index'),
            status: status,
            isEnglish: previewText.isEnglish,
          );
    final number = Padding(
      padding: const EdgeInsets.only(top: 2, right: 8),
      child: Text(
        '${index + 1}',
        key: Key('ocr-medication-number-$index'),
        semanticsLabel: previewText.isEnglish
            ? 'Medication ${index + 1}'
            : '${index + 1}번 약',
        style: const TextStyle(
          color: MedBuddyColors.textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final editLabel = previewText.editCell(
      previewText.medicationName,
      schedule.displayNameForLanguage(previewText.language),
    );
    final editableName = _EditableMedicationCell(
      cellKey: Key('ocr-table-cell-$index-name'),
      semanticsLabel: editLabel,
      onTap: onEditRequested,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          number,
          Expanded(child: name),
        ],
      ),
    );
    final editButton = IconButton(
      key: Key('ocr-medication-edit-$index'),
      tooltip: editLabel,
      onPressed: onEditRequested,
      style: IconButton.styleFrom(fixedSize: const Size(48, 48)),
      icon: const Icon(
        Icons.edit_outlined,
        size: 18,
        color: MedBuddyColors.primaryDark,
      ),
    );
    // 큰 글씨에서는 약명을 좁히지 않고 상태·순번을 다음 줄 오른쪽에 둔다.
    return ResponsiveCardHeader.builder(
      title: editableName,
      actionsBuilder: (context, isStacked, maxWidth) => Row(
        mainAxisSize: isStacked ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (badge != null)
            isStacked
                ? Flexible(child: badge)
                : ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth * .25),
                    child: badge,
                  ),
          editButton,
          toggle,
        ],
      ),
    );
  }
}

// 함수이름: _lookupStatusPresentation
// 함수역할: 확정·후보·미발견·실패·재조회 필요 상태를 문구와 의미 색상으로 변환한다.
// 매개변수: status (MedicationLookupStatus): 조회 상태; isEnglish (bool): 영어 여부.
// 반환값: (String, Color, Color): 문구·전경색·배경색.
(String, Color, Color) _lookupStatusPresentation(
  MedicationLookupStatus status,
  bool isEnglish,
) => switch (status) {
  MedicationLookupStatus.verified => (
    isEnglish ? 'Medicine found' : '약품 확인됨',
    MedBuddyColors.primaryDark,
    MedBuddyColors.successSurface,
  ),
  MedicationLookupStatus.candidates => (
    isEnglish ? 'Check candidates' : '후보 확인 필요',
    MedBuddyColors.reminderAccent,
    MedBuddyColors.warningSurface,
  ),
  MedicationLookupStatus.notFound => (
    isEnglish ? 'No match found' : '약품을 찾지 못함',
    MedBuddyColors.textMuted,
    MedBuddyColors.surfaceSubtle,
  ),
  MedicationLookupStatus.failed => (
    isEnglish ? 'Lookup failed' : '조회 실패',
    MedBuddyColors.danger,
    MedBuddyColors.dangerSurface,
  ),
  MedicationLookupStatus.pending => (
    isEnglish ? 'Lookup needed' : '다시 조회 필요',
    MedBuddyColors.infoBlue,
    MedBuddyColors.lavenderSurface,
  ),
};

// 클래스명: _MedicationLookupBadge
// 역할: 약품 조회 결과의 짧은 상태 배지.
// 주요 책임: 공통 상태 문구·색상 규칙으로 검토 필요와 실패를 구분한다.
// 속성: status (MedicationLookupStatus): 상태; isEnglish (bool): 언어.
class _MedicationLookupBadge extends StatelessWidget {
  final MedicationLookupStatus status;
  final bool isEnglish;

  // 함수이름: _MedicationLookupBadge
  // 함수역할: 표시할 조회 상태와 언어를 받는다.
  // 매개변수: key (Key?): 식별 키; status (MedicationLookupStatus): 상태; isEnglish (bool): 언어.
  // 반환값: 새 _MedicationLookupBadge.
  const _MedicationLookupBadge({
    super.key,
    required this.status,
    required this.isEnglish,
  });

  // 함수이름: build
  // 함수역할: 조회 상태의 공통 문구와 전경·배경색으로 배지를 만든다.
  // 매개변수: context (BuildContext): 표시 위치.
  // 반환값: 중앙 정렬 상태 배지 Container.
  @override
  Widget build(BuildContext context) {
    final (label, foreground, background) = _lookupStatusPresentation(
      status,
      isEnglish,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: MedBuddyRadii.small,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// 클래스명: _CorrectionBadge
// 역할: 약명 보정 또는 확인 필요 표식을 담당한다.
// 주요 책임:
// - 부모가 전달한 표시값과 동작을 반영해 약명 보정 또는 확인 필요 표식 위젯을 구성한다.
// 속성:
// - label (String): 입력란·선택지·명령을 구분해 표시할 문구.
// - isWarning (bool): 경고 색상과 강조를 사용할지 여부.
class _CorrectionBadge extends StatelessWidget {
  final String label;
  final bool isWarning;

  // Function Name: _CorrectionBadge
  // Description: Configure a medication-name correction or review-needed label with optional warning emphasis.
  // Parameters:
  // - key (Key?): Identify this badge within the medication row.
  // - label (String): Correction or review status text to display.
  // - isWarning (bool): Use warning rather than normal correction styling; defaults to false.
  // Returns: A configured _CorrectionBadge.
  const _CorrectionBadge({
    super.key,
    required this.label,
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
        color: isWarning
            ? MedBuddyColors.warningSurface
            : MedBuddyColors.successSurface,
        borderRadius: MedBuddyRadii.pill,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isWarning
              ? MedBuddyColors.reminderAccent
              : MedBuddyColors.primaryDark,
          fontSize: 10,
          fontWeight: FontWeight.w700,
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
// - initialField (_MedicationScheduleEditField): 편집 창에서 선택할 복약 정보 입력 항목.
// - isNewSchedule (bool): 기존 일정 수정이 아니라 새 약품 추가인지 여부.
class _MedicationScheduleEditDialog extends StatefulWidget {
  final MedicationSchedule medicationSchedule;
  final _PreviewText previewText;
  final _MedicationScheduleEditField initialField;
  final bool isNewSchedule;

  // 함수이름: _MedicationScheduleEditDialog
  // 함수역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집에 필요한 입력값과 표시 설정을 초기화한다.
  // 매개변수:
  // - medicationSchedule (MedicationSchedule): 약품명·용량·일수·시간대·완료 상태를 담은 복약 일정.
  // - previewText (_PreviewText): 해당 화면 구역의 언어별 표시 문구.
  // - initialField (_MedicationScheduleEditField): 편집 창에서 선택할 복약 정보 입력 항목.
  // - isNewSchedule (bool): 기존 일정 수정이 아니라 새 약품 추가인지 여부.
  // 반환값: 입력 설정이 반영된 _MedicationScheduleEditDialog 인스턴스.
  const _MedicationScheduleEditDialog({
    required this.medicationSchedule,
    required this.previewText,
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
// 역할: OCR 약명과 일정 입력값을 편집하는 대화상자 상태.
// 주요 책임: 원본값 복원과 입력·시간대 검증을 거쳐 수정 일정을 반환한다.
// 속성: _formKey (GlobalKey<FormState>): 검증; _nameController/_dosageController/_frequencyController/_daysController/_prescriptionDateController (TextEditingController): 입력; _selectedSlotKeys (Set<String>): 시간대; _restoreOriginalName/_asNeeded (bool): 편집 모드.
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
  late bool _asNeeded;

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
      text: formatJsonDate(
        widget.medicationSchedule.prescriptionDate ?? DateTime.now(),
      )!,
    );
    _selectedSlotKeys = widget.medicationSchedule.slotKeys.toSet();
    _asNeeded = widget.medicationSchedule.isAsNeeded;
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

    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.isNewSchedule ? text.addTitle : text.editTitle,
        style: TextStyle(
          color: MedBuddyColors.textStrong,
          fontSize: 21,
          fontWeight: FontWeight.w700,
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
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('ocr-edit-dosage'),
                controller: _dosageController,
                autofocus:
                    widget.initialField == _MedicationScheduleEditField.dosage,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: text.dosage),
              ),
              const SizedBox(height: 16),
              MedicationDosingModeSelector(
                keyPrefix: 'ocr-edit',
                isAsNeeded: _asNeeded,
                isEnglish: text.isEnglish,
                onChanged: (value) => setState(() {
                  _asNeeded = value;
                  _showSlotValidationError = false;
                  if (!value &&
                      isAsNeededDoseInstruction(_frequencyController.text)) {
                    _frequencyController.clear();
                    _selectedSlotKeys.clear();
                  }
                }),
              ),
              const SizedBox(height: 16),
              if (!_asNeeded)
                TextFormField(
                  key: const Key('ocr-edit-frequency'),
                  controller: _frequencyController,
                  autofocus:
                      widget.initialField ==
                      _MedicationScheduleEditField.dailyFrequency,
                  inputFormatters: [LengthLimitingTextInputFormatter(40)],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: text.dailyFrequency,
                    // 매일 복용하지 않는 지시는 어떤 날에 일정이 생기는지 저장 전에 알려 준다.
                    helperText: _doseRhythmNotice,
                    helperMaxLines: 8,
                  ),
                  onChanged: _updateDailyFrequency,
                  validator: _validateDailyFrequency,
                ),
              if (!_asNeeded) const SizedBox(height: 16),
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
                // 총 투약일에 따라 복용 횟수 안내가 달라지므로 다시 그린다.
                onChanged: (_) => setState(() {}),
                validator: _validateMedicationDays,
                // 함수이름: build.onFieldSubmitted callback
                // 함수역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집에서 캡처된 작업 `_submit()`을 실행한다.
                // 매개변수:
                // - _ (콜백 계약에서 추론): 호출 계약상 전달되지만 본문에서는 사용하지 않는 인수.
                // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                onFieldSubmitted: (_) => _submit(),
              ),
              if (!_asNeeded) ...[
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text.scheduleSlots,
                    style: TextStyle(
                      color: MedBuddyColors.textStrong,
                      fontSize: 14,
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
                  child: MedicationEntrySlotChoices(
                    keyPrefix: 'ocr-edit-slot',
                    values: _selectedSlotKeys,
                    label: text.slotLabel,
                    // 함수이름: build.onChanged callback
                    // 함수역할: 실제 복약 시간대와 표시 횟수를 함께 갱신한다.
                    // 매개변수:
                    // - slotKey (String): 선택을 바꾼 복약 시간대 키.
                    // - selected (콜백 계약에서 추론): 현재 선택 집합에 포함되는지 여부.
                    // 반환값: 캡처한 상호작용의 완료. 화면 결과·상태 변경은 연결된 작업에서 처리한다.
                    onChanged: (slotKey, selected) {
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
                        // "주 1회" 같은 지시를 시간대 개수로 덮어쓰면 매일 복용으로 바뀐다.
                        if (_selectedSlotKeys.isNotEmpty &&
                            !requiresDoseScheduleReview(
                              _frequencyController.text,
                            ) &&
                            readDoseCycle(_frequencyController.text).isDaily) {
                          _frequencyController.text = _canonicalDailyFrequency(
                            _selectedSlotKeys.length,
                          );
                        }
                        _showSlotValidationError = false;
                      });
                    },
                  ),
                ),
              ],
              if (_showSlotValidationError) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text.scheduleSlotRequired,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
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

  // 함수이름: _readDailyFrequency
  // 함수역할: 지원하는 하루 1~4회 입력을 읽고 음수·소수·모호한 문구는 추측하지 않는다.
  // 매개변수: value 사용자가 확인한 횟수. 반환값: 유효한 횟수 또는 null.
  int? _readDailyFrequency(String value) {
    final match = RegExp(
      r'^(?:(?:1\s*일|하루(?:에)?)\s*)?([1-4])\s*(?:회|번|times?|x)?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  // Function Name: _canonicalDailyFrequency
  // Description: Canonicalizes daily frequency to the same N회 representation used by review and server examples, avoiding false schedule-change comparisons.
  // Parameters: count (int): doses per day.
  // Returns: The canonical daily-frequency string.
  String _canonicalDailyFrequency(int count) => '$count회';

  // Function Name: _isDailyFrequencyUntouched
  // Description: Checks whether the frequency text is unchanged from the initially displayed value.
  // Parameters: value (String): current frequency input.
  // Returns: True when the original frequency text is retained.
  bool _isDailyFrequencyUntouched(String value) =>
      value.trim() == widget.medicationSchedule.intakeTime.trim();

  // Function Name: _updateDailyFrequency
  // Description: Updates default dose slots when the dose count changes, preserving custom slots when the count stays the same.
  // Parameters: value (String): edited frequency.
  // Returns: None.
  void _updateDailyFrequency(String value) {
    final count = _readDailyFrequency(value);
    // 시간대가 바뀌지 않아도 복용 요일 안내는 입력에 따라 달라진다.
    setState(() {
      if (count == null || count == _selectedSlotKeys.length) return;
      _selectedSlotKeys = medicationScheduleSlotKeysForFrequency(count).toSet();
      _showSlotValidationError = false;
    });
  }

  // Function Name: _doseRhythmNotice
  // Description: Explains scheduled days and course dose count when the entered instruction is not daily.
  // Parameters: None.
  // Returns: The rhythm notice, or null for daily dosing.
  String? get _doseRhythmNotice {
    final cycle = readDoseCycle(_frequencyController.text);
    if (cycle.isDaily) return null;
    return widget.previewText.doseRhythmNotice(
      cycle,
      startDate: _parseDate(_prescriptionDateController.text.trim()),
      courseDays: int.tryParse(_daysController.text.trim()) ?? 0,
    );
  }

  // 함수이름: _validateDailyFrequency
  // 함수역할: 해석하지 못한 횟수로 기존 시간대가 조용히 저장되는 것을 막는다. 손대지 않은 OCR 횟수("8시간마다" 등)는 다른 항목 수정을 막지 않도록 그대로 통과시키고, "주 1회"·"격일"처럼 복용하는 날을 읽을 수 있는 지시는 받아들인다.
  // 매개변수: value 횟수 입력. 반환값: 잘못된 입력 안내 또는 null.
  String? _validateDailyFrequency(String? value) =>
      _asNeeded ||
          (!requiresDoseScheduleReview(value) &&
              (_isDailyFrequencyUntouched(value ?? '') ||
                  _readDailyFrequency(value ?? '') != null ||
                  !readDoseCycle(value).isDaily))
      ? null
      : widget.previewText.invalidDailyFrequency;

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
    if (!isValidMedicationCourseDays(int.tryParse(trimmedValue))) {
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

  // Function Name: _minimumPrescriptionDate
  // Description: Reads the earliest prescription date from shared schedule limits.
  // Parameters: None.
  // Returns: The minimum allowed DateTime.
  DateTime get _minimumPrescriptionDate => earliestMedicationStartDate();

  // Function Name: _maximumPrescriptionDate
  // Description: Reads the latest prescription date from shared schedule limits relative to today.
  // Parameters: None.
  // Returns: The maximum allowed DateTime.
  DateTime get _maximumPrescriptionDate =>
      latestMedicationStartDate(DateTime.now());

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
    // 함수역할: OCR 약명·조제일·용량·횟수·일수·시간대 편집의 입력·요청 상태를 `_prescriptionDateController.text = formatJsonDate(selectedDate)!`로 갱신한다.
    // 매개변수:
    // - 없음.
    // 반환값: 별도 결과 없음. 캡처한 상태 변경을 적용한다.
    setState(() {
      _prescriptionDateController.text = formatJsonDate(selectedDate)!;
    });
  }

  // 함수이름: _submit
  // 함수역할: 수정 입력값을 검증하고 변경된 복약 일정 객체를 호출 화면으로 반환한다.
  // 매개변수:
  // - 없음.
  // 반환값: 없음. 위 동작의 상태 변경 또는 화면 처리를 수행한다.
  void _submit() {
    final hasSelectedSlot = _asNeeded || _selectedSlotKeys.isNotEmpty;
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
    // 손대지 않은 횟수는 그대로 두고, 바꾼 횟수만 "N회" 표기로 맞춘다.
    final frequencyText = _frequencyController.text.trim();
    final frequencyCount = _isDailyFrequencyUntouched(frequencyText)
        ? null
        : _readDailyFrequency(frequencyText);

    Navigator.pop(
      context,
      widget.medicationSchedule.copyWith(
        medicationName: medicationName,
        dosage: _dosageController.text.trim(),
        intakeTime: _asNeeded
            ? '필요시 복용'
            : frequencyCount == null
            ? frequencyText
            : _canonicalDailyFrequency(frequencyCount),
        medicationTime: int.tryParse(_daysController.text.trim()) ?? 0,
        prescriptionDate: _parseDate(_prescriptionDateController.text.trim()),
        dosingMode: _asNeeded ? 'as_needed' : 'scheduled',
        scheduleSlotKeys: _asNeeded
            ? []
            : medicationScheduleSlotKeys
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

  // Function Name: isEnglish
  // Description: Applies the shared English-language rule to preview/editor labels.
  // Parameters: None.
  // Returns: True for an English language code.
  bool get isEnglish => isEnglishLanguage(language);

  // 함수이름: back
  // 함수역할: 현재 언어와 입력값에 맞춰 "뒤로가기" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get back => isEnglish ? 'Back' : '뒤로가기';
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
      isEnglish ? 'Retry search' : '미확인 약 다시 조회';
  // 함수이름: continueWithVerifiedOnly
  // 함수역할: 현재 언어와 입력값에 맞춰 "확인된 약만으로 계속" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get continueWithVerifiedOnly =>
      isEnglish ? 'Use verified only' : '확인된 약만으로 계속';
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
  // Function Name: invalidDailyFrequency
  // Description: Explains the supported dose-frequency input range.
  // Parameters: None.
  // Returns: The localized frequency-validation message.
  String get invalidDailyFrequency => isEnglish
      ? 'Enter a daily frequency from 1 to 4, or a schedule such as "주 1회" or "격일".'
      : '1일 횟수를 1~4회로 입력하거나 "주 1회", "격일"처럼 입력해주세요.';
  // Function Name: notDailyBadge
  // Description: Marks a medication that is not taken every day in the review table.
  // Parameters: None.
  // Returns: The localized non-daily badge.
  String get notDailyBadge => isEnglish ? 'Not daily' : '매일 아님';
  // Function Name: doseRhythmNotice
  // Description: Explains which dates a non-daily schedule uses and how many doses occur within the course.
  // Parameters: cycle: parsed dose rhythm; startDate: optional first dose date; courseDays: course length, zero when not entered.
  // Returns: The localized dose-rhythm explanation.
  String doseRhythmNotice(
    DoseCycle cycle, {
    required DateTime? startDate,
    required int courseDays,
  }) => describeDoseCycle(
    cycle,
    isEnglish: isEnglish,
    startDate: startDate,
    courseDays: courseDays,
  );
  // 함수이름: invalidTotalDays
  // 함수역할: 현재 언어와 입력값에 맞춰 "1일 이상 3650일 이하의 숫자를 입력해주세요." 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get invalidTotalDays => isEnglish
      ? 'Enter a number between 1 and $maxMedicationCourseDays.'
      : '1일 이상 $maxMedicationCourseDays일 이하의 숫자를 입력해주세요.';
  // 함수이름: medicationStartDate
  // 함수역할: 현재 언어와 입력값에 맞춰 "복용 시작일" 문구를 제공한다.
  // 매개변수:
  // - 없음.
  // 반환값: 위 규칙으로 선택·가공한 표시 문구 또는 식별 문자열.
  String get medicationStartDate => isEnglish ? 'Start date' : '복용 시작일';

  // Function Name: slotLabel
  // Description: Resolves a dose-slot key to the shared localized name while preserving unknown keys.
  // Parameters: slotKey (String): dose-slot identifier.
  // Returns: The localized label or original key.
  String slotLabel(String slotKey) =>
      medicationSlotLabel(slotKey, isEnglish: isEnglish);

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

  // Function Name: dateValue
  // Description: Formats the prescription date as year-month-day with a missing-information fallback.
  // Parameters: date (DateTime?): prescription date.
  // Returns: The date string or localized missing-information label.
  String dateValue(DateTime? date) => formatJsonDate(date) ?? noInformation;

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
