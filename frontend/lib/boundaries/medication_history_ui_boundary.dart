// 파일명: medication_history_ui_boundary.dart
// 역할: 환자·보호자의 날짜별 복약 이력, 정정 확인, 개인정보 안내 후 CSV 공유를 제공한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controls/medication_history_control.dart';
import '../controls/share_medication_history_control.dart';
import '../entities/medication_history_entity.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../widgets/medication_history_month_calendar.dart';
import '../entities/medication_history_export.dart';
import '../services/api_response_parser.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/medication_entry_fields.dart';
import '../widgets/medbuddy_page_header.dart';

enum _HistoryShareDestination { csv, chat }

// 클래스명: MedicationHistoryUI
// 역할: 외부 탐색 화면에서 환자 범위·읽기 전용 권한·언어·갱신 콜백을 전달받는다.
class MedicationHistoryUI extends StatefulWidget {
  // 함수역할: 이력 화면의 대상과 권한을 고정한다. control 주입 시 부모가 객체를 소유한다.
  const MedicationHistoryUI({
    super.key,
    required this.patientHash,
    this.readOnly = false,
    this.isEnglish = false,
    this.onChanged,
    this.control,
    this.currentUserHash,
    this.chatShareControl,
    this.sharedRange,
    this.initiallyShowExport = false,
  });

  final String patientHash;
  final bool readOnly;
  final bool isEnglish;
  final FutureOr<void> Function()? onChanged;
  final MedicationHistoryControl? control;
  final String? currentUserHash;
  final ShareMedicationHistory? chatShareControl;
  // 채팅에서 연 상세 화면은 공유 기간의 최신 자료만 읽기 전용으로 조회한다.
  final MedicationHistoryRange? sharedRange;
  // 기능 검색에서 공유를 선택해도 전송은 하지 않고 기존 기간·대상 확인창만 연다.
  final bool initiallyShowExport;

  // 함수역할: 조회·정정·내보내기 수명을 관리할 화면 상태를 만든다.
  @override
  State<MedicationHistoryUI> createState() => _MedicationHistoryUIState();
}

// 클래스명: _MedicationHistoryUIState
// 역할: 기간 선택과 서버 결과를 표시하고 세션·화면 수명이 바뀐 뒤의 작업을 폐기한다.
class _MedicationHistoryUIState extends State<MedicationHistoryUI>
    with WidgetsBindingObserver {
  static const _exportChannel = MethodChannel('com.medbuddy/data_export');
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late MedicationHistoryControl _control;
  late MedicationHistoryRange _range;
  bool _ownsControl = false;
  ShareMedicationHistory? _chatShare;
  bool get _readOnly => widget.readOnly || widget.sharedRange != null;
  bool _interactionActive = false;
  bool _exporting = false;
  // 화면은 한 달 달력에서 시작하고, 날짜를 누르면 그날의 기록으로 들어간다.
  bool _showMonth = true;
  late DateTime _month;
  MedicationHistorySnapshot? _monthSnapshot;
  bool _monthFailed = false;

  // 함수역할: 현재 화면 언어에 해당하는 문구를 선택한다.
  String tr(String ko, String en) => widget.isEnglish ? en : ko;

  // 함수역할: 앱 복귀 감시와 최초 7일 조회를 준비한다.
  // 날짜 탐색 화면에서는 최초 조회를 오늘 하루로 제한한다.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindControl();
  }

  // 함수역할: 제어 객체의 환자·권한을 화면과 비교하고 첫 프레임 뒤 조회를 예약한다.
  void _bindControl() {
    _ownsControl = widget.control == null;
    _control =
        widget.control ??
        MedicationHistoryControl(
          patientHash: widget.patientHash,
          readOnly: _readOnly,
        );
    if (_control.patientHash != widget.patientHash.trim() ||
        _control.readOnly != _readOnly) {
      throw ArgumentError(
        'The history control must match the screen patient and permissions.',
      );
    }
    _chatShare = widget.chatShareControl;
    final sender = widget.currentUserHash;
    if (_chatShare != null &&
        (_chatShare!.patientHash != widget.patientHash ||
            _chatShare!.userHash != sender)) {
      throw ArgumentError(
        'The share control must match the sender and patient.',
      );
    }
    if (_chatShare == null && sender != null && sender.trim().isNotEmpty) {
      _chatShare = ShareMedicationHistory(
        userHash: sender,
        patientHash: widget.patientHash,
        ensureSession: _control.ensureSession,
        now: () => _control.now,
        isEnglish: widget.isEnglish,
      );
    }
    _range =
        widget.sharedRange ??
        MedicationHistoryRange(_control.today, _control.today);
    _month = DateTime.utc(_control.today.year, _control.today.month);
    _showMonth = widget.sharedRange == null;
    _monthSnapshot = null;
    _monthFailed = false;
    final bound = _control;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(bound, _control)) {
        unawaited(_loadInitial(bound));
      }
    });
  }

  // 함수이름: _loadInitial
  // 함수역할: 최초 조회가 성공하고 같은 계정 화면일 때만 요청된 내보내기 확인창을 연다.
  Future<void> _loadInitial(MedicationHistoryControl bound) async {
    await _reload();
    if (!_isCurrent(bound) || !widget.initiallyShowExport || _readOnly) return;
    if ((_showMonth ? _monthSnapshot : _control.snapshot) != null) {
      await _export();
    }
  }

  String get _recordNotice => tr(
    '사용자가 입력한 기록이며 실제 복용을 증명하지 않습니다. 미기록은 미복용을 뜻하지 않습니다.',
    'Self-reported records are not proof of ingestion. Unrecorded does not mean not taken.',
  );

  String get _timeZoneNotice =>
      tr('시각 기준: 한국 시간(UTC+09:00)', 'Time zone: Korea (UTC+09:00)');

  // 상시 본문 대신 정보 버튼에서 동일한 기록 해석·시간대 안내를 다시 확인한다.
  Future<void> _showRecordNotice() async {
    if (_locked) return;
    final control = _control;
    _messengerKey.currentState?.hideCurrentSnackBar();
    setState(() => _interactionActive = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('복약 기록 안내', 'About medication records')),
          scrollable: true,
          content: Text('$_recordNotice\n\n$_timeZoneNotice'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('닫기', 'Close')),
            ),
          ],
        ),
      );
    } finally {
      if (mounted && identical(control, _control)) {
        setState(() => _interactionActive = false);
      }
    }
  }

  // 함수역할: 부모가 환자나 권한을 바꾸면 이전 자료·대화상자를 무효화하고 새 범위를 연결한다.
  @override
  void didUpdateWidget(covariant MedicationHistoryUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientHash != widget.patientHash ||
        oldWidget.readOnly != widget.readOnly ||
        oldWidget.currentUserHash != widget.currentUserHash ||
        oldWidget.chatShareControl != widget.chatShareControl ||
        oldWidget.sharedRange != widget.sharedRange ||
        oldWidget.control != widget.control) {
      if (oldWidget.chatShareControl == null) _chatShare?.dispose();
      _control.invalidateSession();
      if (_ownsControl) _control.dispose();
      _interactionActive = false;
      _exporting = false;
      _bindControl();
    }
  }

  // 함수역할: 앱 복귀 때 세션을 확인하고 편집·공유 중이 아니면 서버 기록을 다시 읽는다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    try {
      _control.ensureSession();
    } catch (_) {
      return;
    }
    if (!_control.busy && !_interactionActive && !_exporting) {
      unawaited(_reload());
    }
  }

  // 함수역할: 앱 수명 감시와 화면이 직접 소유한 제어 객체만 해제한다.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.chatShareControl == null) _chatShare?.dispose();
    if (_ownsControl) _control.dispose();
    super.dispose();
  }

  // 함수역할: 선택 범위를 조회하고 실패 표시와 재시도 상태는 제어 객체에 맡긴다.
  Future<void> _load() async {
    try {
      await _control.load(_range);
    } catch (_) {
      // 서버·네트워크 오류는 제어 객체의 상태로 표시하고 이전 자료는 남기지 않는다.
    }
  }

  // 함수역할: 지금 보이는 달력 또는 하루 기록을 다시 읽는다.
  Future<void> _reload() => _showMonth ? _loadMonth() : _load();

  // 함수역할: 보이는 달의 조회 가능한 날짜를 한 번에 읽어 날짜별 복용 기록 요약을 만든다.
  //   하루 기록 화면의 자료는 바꾸지 않으며, 실패하면 달력 아래에 재시도를 보여 준다.
  Future<void> _loadMonth() async {
    final control = _control;
    final range = MedicationHistoryMonthCalendar.visibleRange(
      _month,
      control.today,
    );
    if (range == null || control.busy) return;
    setState(() => _monthFailed = false);
    try {
      final snapshot = await control.readRange(range);
      if (!_isCurrent(control) || !_showMonth) return;
      setState(() => _monthSnapshot = snapshot);
    } catch (_) {
      if (mounted && identical(control, _control)) {
        setState(() {
          _monthSnapshot = null;
          _monthFailed = true;
        });
      }
    }
  }

  // 함수역할: 달력에서 고른 날짜의 기록 화면으로 들어간다.
  Future<void> _openDay(DateTime day) async {
    if (_locked) return;
    setState(() => _showMonth = false);
    await _selectDay(day);
  }

  // 함수역할: 하루 기록에서 그 날짜가 속한 달의 달력으로 돌아가 최신 요약을 읽는다.
  Future<void> _openMonth() async {
    if (_locked) return;
    setState(() {
      _showMonth = true;
      _month = DateTime.utc(_range.start.year, _range.start.month);
    });
    await _loadMonth();
  }

  // 함수역할: 다른 달로 이동하고 그 달의 요약을 읽는다.
  Future<void> _changeMonth(DateTime month) async {
    if (_locked) return;
    setState(() {
      _month = month;
      _monthSnapshot = null;
    });
    await _loadMonth();
  }

  // 함수역할: 비동기 작업의 화면·제어 객체·세션이 아직 같은지 확인한다.
  bool _isCurrent(MedicationHistoryControl control) {
    if (!mounted || !identical(control, _control)) return false;
    try {
      control.ensureSession();
      return true;
    } catch (_) {
      return false;
    }
  }

  // 함수역할: 현재 화면에 완료 또는 실패 안내를 읽을 수 있는 시간 동안 표시한다.
  void _message(String message) {
    if (!mounted) return;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
  }

  // 함수역할: 요청·대화상자·공유·세션 무효화 중인지 반환해 명령 중복을 막는다.
  bool get _locked =>
      _control.busy ||
      _interactionActive ||
      _exporting ||
      _control.sessionInvalidated;

  // 함수역할: 최근 90일 달력에서 최대 31일을 선택하고 확인한 범위만 조회한다.
  // 기간 선택은 내보내기에만 사용하고 화면의 달력은 하루를 선택한다.
  Future<void> _pickRange() async {
    if (_locked) return;
    final control = _control;
    setState(() => _interactionActive = true);
    try {
      final today = control.today;
      final earliest = today.subtract(const Duration(days: 89));
      final selection = await showDatePicker(
        context: context,
        locale: Locale(widget.isEnglish ? 'en' : 'ko'),
        firstDate: earliest,
        lastDate: today,
        currentDate: today,
        initialDate: _range.start.isBefore(earliest)
            ? earliest
            : _range.start.isAfter(today)
            ? today
            : _range.start,
        helpText: tr('복약 기록 날짜 선택', 'Select a record date'),
        confirmText: tr('조회', 'Apply'),
      );
      if (selection == null || !_isCurrent(control)) return;
      final range = MedicationHistoryRange(selection, selection);
      try {
        range.validate(control.now);
      } on FormatException {
        _message(
          tr(
            '한 번에 최대 31일까지 선택할 수 있어요.',
            'Select no more than 31 days at a time.',
          ),
        );
        return;
      }
      setState(() => _range = range);
      await _load();
    } finally {
      if (mounted && identical(control, _control)) {
        setState(() => _interactionActive = false);
      }
    }
  }

  // 함수역할: 오늘까지 입력 일수의 기간을 선택하고 새 결과를 읽는다.
  Future<void> _selectDay(DateTime day) async {
    if (_locked) return;
    if (day.isBefore(_control.today.subtract(const Duration(days: 89))) ||
        day.isAfter(_control.today)) {
      return;
    }
    final range = MedicationHistoryRange(day, day);
    range.validate(_control.now);
    setState(() {
      _range = range;
    });
    await _load();
  }

  // 함수역할: 환자 본인에게만 정정 또는 새 필요시 기록을 열고 서버 저장 확인 뒤 부모 화면을 갱신한다.
  Future<void> _edit(MedicationHistoryEntry? entry) async {
    if (_locked || _readOnly) return;
    final control = _control;
    final snapshot = control.snapshot;
    if (snapshot == null || !_isCurrent(control)) return;
    setState(() => _interactionActive = true);
    try {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _MedicationHistoryEditor(
          control: control,
          entry: entry,
          snapshot: snapshot,
          isEnglish: widget.isEnglish,
        ),
      );
      if (!_isCurrent(control)) return;
      if (changed == true) {
        _message(tr('복약 기록을 저장했어요.', 'The record was saved.'));
        try {
          await widget.onChanged?.call();
        } catch (_) {
          if (_isCurrent(control)) {
            _message(
              tr(
                '기록은 저장됐지만 다른 화면을 새로고침하지 못했어요.',
                'The record was saved, but other screens could not refresh.',
              ),
            );
          }
        }
      }
      // 충돌·응답 유실 후 닫아도 서버의 최종 상태를 다시 확인한다.
      if (_isCurrent(control)) await _load();
    } finally {
      if (mounted && identical(control, _control)) {
        setState(() => _interactionActive = false);
      }
    }
  }

  // 함수역할: 선택 기간 요약과 민감정보 안내를 확인받아 CSV 공유 창을 열며 전송 완료로 주장하지 않는다.
  Future<void> _export() async {
    if (_locked) return;
    final control = _control;
    // 달력에서는 보이는 달, 하루 기록에서는 그날을 공유 기간의 시작값으로 쓴다.
    var snapshot = _showMonth ? _monthSnapshot : control.snapshot;
    if (snapshot == null || !_isCurrent(control)) return;
    var exportRange = snapshot.range;
    var selectingDate = false;
    var preparingExport = false;
    String? exportError;

    // 날짜 선택은 공유 창 안에서만 바꾸고 날짜별 기록 화면은 유지한다.
    // CSV는 31일씩 나눠 읽어 최근 90일 전체를 담을 수 있고, 채팅 공유는 서버가 한 번에 31일만 받는다.
    String? rangeError() {
      if (exportRange.start.isAfter(exportRange.end)) {
        return tr(
          '종료일은 시작일보다 빠를 수 없어요.',
          'End date cannot be before start date.',
        );
      }
      try {
        exportRange.validate(
          control.now,
          maxDays: MedicationHistoryRange.maximumExportDays,
        );
        return null;
      } on FormatException {
        return tr(
          '최근 90일 안에서 선택해 주세요.',
          'Select dates within the last 90 days.',
        );
      }
    }

    String? chatRangeError() {
      final error = rangeError();
      if (error != null) return error;
      return exportRange.days > MedicationHistoryRange.maximumReadDays
          ? tr(
              '채팅 공유는 최대 31일까지예요. CSV는 90일까지 공유할 수 있어요.',
              'Chat sharing covers up to 31 days; a CSV can cover up to 90.',
            )
          : null;
    }

    Future<void> pickExportDate(
      BuildContext dialogContext,
      StateSetter updateDialog, {
      required bool start,
    }) async {
      if (selectingDate || preparingExport || !_isCurrent(control)) return;
      updateDialog(() => selectingDate = true);
      try {
        final today = control.today;
        final earliest = today.subtract(const Duration(days: 89));
        final initial = start ? exportRange.start : exportRange.end;
        final selected = await showDatePicker(
          context: dialogContext,
          locale: Locale(widget.isEnglish ? 'en' : 'ko'),
          firstDate: earliest,
          lastDate: today,
          currentDate: today,
          initialDate: initial.isBefore(earliest)
              ? earliest
              : initial.isAfter(today)
              ? today
              : initial,
          helpText: start
              ? tr('시작일 선택', 'Select start date')
              : tr('종료일 선택', 'Select end date'),
        );
        if (selected == null ||
            !_isCurrent(control) ||
            !dialogContext.mounted) {
          return;
        }
        updateDialog(() {
          exportRange = MedicationHistoryRange(
            start ? selected : exportRange.start,
            start ? exportRange.end : selected,
          );
          exportError = null;
        });
      } finally {
        if (dialogContext.mounted) updateDialog(() => selectingDate = false);
      }
    }

    // 공유를 확인한 시점에 선택 기간과 접근 권한을 다시 확인한다.
    Future<void> prepareExport(
      BuildContext dialogContext,
      StateSetter updateDialog,
      _HistoryShareDestination destination,
    ) async {
      if (selectingDate ||
          preparingExport ||
          (destination == _HistoryShareDestination.chat
                  ? chatRangeError()
                  : rangeError()) !=
              null ||
          !_isCurrent(control)) {
        return;
      }
      updateDialog(() {
        preparingExport = true;
        exportError = null;
      });
      try {
        final result = await control.readRangeForExport(exportRange);
        if (!_isCurrent(control) || !dialogContext.mounted) return;
        if (ModalRoute.of(dialogContext)?.isCurrent != true) return;
        snapshot = result;
        Navigator.pop(dialogContext, destination);
      } catch (_) {
        if (_isCurrent(control) && dialogContext.mounted) {
          updateDialog(
            () => exportError = tr(
              '내보낼 기록을 불러오지 못했어요. 다시 시도해 주세요.',
              'Could not load the export records. Please try again.',
            ),
          );
        }
      } finally {
        if (dialogContext.mounted) updateDialog(() => preparingExport = false);
      }
    }

    setState(() => _exporting = true);
    try {
      final destination = await showDialog<_HistoryShareDestination>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, updateDialog) => AnimatedBuilder(
            animation: control,
            builder: (context, _) => control.sessionInvalidated
                ? _sessionEndedDialog(context, widget.isEnglish)
                : AlertDialog(
                    title: Text(tr('복약 기록 공유', 'Share medication history')),
                    scrollable: true,
                    content: SizedBox(
                      width: 400,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Builder(
                              builder: (context) {
                                final buttons = [
                                  for (final start in [true, false])
                                    MedicationEntryDateButton(
                                      buttonKey: Key(
                                        start
                                            ? 'history-export-start'
                                            : 'history-export-end',
                                      ),
                                      label: start
                                          ? tr('시작일', 'Start date')
                                          : tr('종료일', 'End date'),
                                      value: MedicationHistoryDates.format(
                                        start
                                            ? exportRange.start
                                            : exportRange.end,
                                      ),
                                      onPressed:
                                          selectingDate || preparingExport
                                          ? null
                                          : () => pickExportDate(
                                              context,
                                              updateDialog,
                                              start: start,
                                            ),
                                    ),
                                ];
                                if (MediaQuery.sizeOf(context).width < 408 ||
                                    MediaQuery.textScalerOf(context).scale(16) >
                                        20) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      buttons[0],
                                      const SizedBox(height: 8),
                                      buttons[1],
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: buttons[0]),
                                    const SizedBox(width: 12),
                                    Expanded(child: buttons[1]),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _chatShare == null
                                  ? tr(
                                      '최근 90일 · 최대 90일',
                                      'Last 90 days · Up to 90 days',
                                    )
                                  : tr(
                                      '최근 90일 · CSV 최대 90일 · 채팅 최대 31일',
                                      'Last 90 days · CSV up to 90 days · Chat up to 31 days',
                                    ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (rangeError() != null ||
                                (_chatShare != null &&
                                    chatRangeError() != null) ||
                                exportError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  rangeError() ??
                                      (_chatShare == null
                                          ? null
                                          : chatRangeError()) ??
                                      exportError!,
                                  key: const Key('history-export-error'),
                                  style: const TextStyle(
                                    color: MedBuddyColors.danger,
                                  ),
                                ),
                              ),
                            if (preparingExport)
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: LinearProgressIndicator(),
                              ),
                            const SizedBox(height: 16),
                            // 채팅 공유는 서버가 기간과 상태별 횟수만 만들어 보내므로 CSV와 구분해 알린다.
                            Text(
                              key: const Key('history-share-privacy-notice'),
                              _chatShare == null
                                  ? tr(
                                      '약 이름·복용 시각·건너뛴 이유가 포함됩니다. 공유 대상을 확인해 주세요.',
                                      'Includes medication names, taken times and skip reasons. Check who you share with.',
                                    )
                                  : tr(
                                      'CSV에는 약 이름·복용 시각·건너뛴 이유가 포함되고, 채팅에는 기간과 상태별 횟수만 보냅니다. 공유 대상을 확인해 주세요.',
                                      'The CSV includes medication names, taken times and skip reasons; the chat gets only the period and the counts. Check who you share with.',
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      SizedBox(
                        width: 400,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_chatShare != null) ...[
                              FilledButton.icon(
                                key: const Key('history-share-chat'),
                                onPressed:
                                    selectingDate ||
                                        preparingExport ||
                                        chatRangeError() != null
                                    ? null
                                    : () => prepareExport(
                                        context,
                                        updateDialog,
                                        _HistoryShareDestination.chat,
                                      ),
                                icon: const Icon(Icons.chat_bubble_outline),
                                label: Text(tr('채팅으로 공유', 'Share in chat')),
                              ),
                              const SizedBox(height: 8),
                            ],
                            FilledButton.tonalIcon(
                              key: const Key('history-export-share'),
                              onPressed:
                                  selectingDate ||
                                      preparingExport ||
                                      rangeError() != null
                                  ? null
                                  : () => prepareExport(
                                      context,
                                      updateDialog,
                                      _HistoryShareDestination.csv,
                                    ),
                              icon: const Icon(Icons.share_outlined),
                              label: Text(tr('CSV 공유', 'Share CSV')),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(tr('취소', 'Cancel')),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
      if (destination == null || !mounted || !_isCurrent(control)) return;
      final exportSnapshot = snapshot!;
      if (destination == _HistoryShareDestination.chat) {
        final sent = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _HistoryChatShareDialog(
            history: control,
            share: _chatShare!,
            range: exportSnapshot.range,
            isEnglish: widget.isEnglish,
          ),
        );
        if (sent != null && _isCurrent(control)) {
          _message(
            tr('$sent 님과의 채팅에 공유했어요.', 'Shared in your chat with $sent.'),
          );
        }
        return;
      }
      final csv = medicationHistoryCsv(
        exportSnapshot,
        isEnglish: widget.isEnglish,
      );
      final filename =
          'medbuddy_history_${MedicationHistoryDates.format(exportSnapshot.range.start)}_'
          '${MedicationHistoryDates.format(exportSnapshot.range.end)}.csv';
      try {
        await _exportChannel.invokeMethod<void>('shareCsv', {
          'filename': filename,
          // Android 공유 경계가 UTF-8 BOM을 추가하므로 본문은 중복하지 않는다.
          'content': csv.substring(1),
        });
        if (_isCurrent(control)) {
          _message(
            tr(
              '공유 창을 열었어요. 전송 여부는 선택한 앱에서 확인해 주세요.',
              'The share window was opened. Check delivery in the app you choose.',
            ),
          );
        }
      } on MissingPluginException {
        if (_isCurrent(control)) {
          await _offerClipboard(csv.substring(1), control);
        }
      } on PlatformException catch (failure) {
        if (!_isCurrent(control)) return;
        if (const {
          'unimplemented',
          'unsupported',
          'not_implemented',
        }.contains(failure.code)) {
          await _offerClipboard(csv.substring(1), control);
        } else {
          _message(
            tr(
              '파일을 공유하지 못했어요. 다시 시도해 주세요.',
              'The file could not be shared. Please try again.',
            ),
          );
        }
      }
    } catch (_) {
      if (_isCurrent(control)) {
        _message(tr('내보내기를 완료하지 못했어요.', 'The export could not be completed.'));
      }
    } finally {
      if (mounted && identical(control, _control)) {
        setState(() => _exporting = false);
      }
    }
  }

  // 함수역할: 파일 공유 미지원일 때 별도 동의를 받은 경우에만 CSV 본문을 클립보드에 복사한다.
  Future<void> _offerClipboard(
    String csv,
    MedicationHistoryControl control,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          tr(
            '이 기기에서는 파일 공유를 지원하지 않아요',
            'File sharing is unavailable on this device',
          ),
        ),
        content: Text(
          tr(
            '대신 CSV 내용을 클립보드에 복사할까요? 복사한 복약 정보는 다른 앱에서 읽을 수 있습니다.',
            'Copy the CSV text to the clipboard instead? Other apps may be able to read copied medication information.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('취소', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.copy_outlined),
            label: Text(tr('복사', 'Copy')),
          ),
        ],
      ),
    );
    if (accepted != true || !_isCurrent(control)) return;
    await Clipboard.setData(ClipboardData(text: csv));
    if (_isCurrent(control)) {
      _message(
        tr(
          'CSV 내용을 복사했어요. 파일 저장은 되지 않았어요.',
          'CSV text was copied. No file was saved.',
        ),
      );
    }
  }

  // 함수역할: 큰 글씨에서도 스크롤 가능한 날짜·자가 보고 안내·상태·기록 목록을 렌더링한다.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _control,
    builder: (context, _) {
      final snapshot = _control.snapshot;
      final shown = _showMonth ? _monthSnapshot : snapshot;
      final scrollProgress =
          MediaQuery.textScalerOf(context).scale(16) > 22 ||
          MediaQuery.sizeOf(context).height < 600;
      final header = MedBuddyPageHeader(
        title: tr('복약 기록', 'Medication history'),
        subtitle: widget.sharedRange != null
            ? tr(
                '공유 기간의 최신 기록 · 읽기 전용',
                'Latest records for the shared period · Read only',
              )
            : _readOnly
            ? tr('환자 기록 · 읽기 전용', 'Patient records · Read only')
            : tr('날짜별 복용 기록입니다.', 'Daily medication records.'),
        onBackRequested: () => Navigator.maybePop(context),
        actions: [
          IconButton(
            tooltip: tr('새로고침', 'Refresh'),
            onPressed: _locked ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: tr('내보내기', 'Export'),
            onPressed: _locked || shown == null ? null : _export,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
        bottom: shown == null ? null : _progress(shown),
      );
      // 하루 기록에서 뒤로 가면 달력으로 돌아가고, 달력에서 뒤로 가면 화면을 닫는다.
      return PopScope(
        canPop: _showMonth || widget.sharedRange != null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_openMonth());
        },
        child: ScaffoldMessenger(
          key: _messengerKey,
          child: Scaffold(
            backgroundColor: MedBuddyColors.pageBackground,
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  if (!scrollProgress) header,
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ListView(
                          // 달력과 하루 기록을 오갈 때마다 목록을 맨 위에서 시작한다.
                          key: ValueKey(_showMonth ? 'month' : 'day'),
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (scrollProgress) header,
                            if (widget.sharedRange != null)
                              ..._sharedPeriodBody(snapshot)
                            else if (_showMonth)
                              ..._monthBody()
                            else ...[
                              Row(
                                key: const Key('history-date-navigation'),
                                children: [
                                  IconButton(
                                    key: const Key('history-open-month'),
                                    tooltip: tr('달력으로 보기', 'Show the month'),
                                    onPressed: _locked ? null : _openMonth,
                                    icon: const Icon(
                                      Icons.calendar_month_outlined,
                                    ),
                                  ),
                                  IconButton(
                                    key: const Key('history-previous-day'),
                                    tooltip: tr('이전 날짜', 'Previous day'),
                                    onPressed:
                                        _locked ||
                                            !_range.start.isAfter(
                                              _control.today.subtract(
                                                const Duration(days: 89),
                                              ),
                                            )
                                        ? null
                                        : () => _selectDay(
                                            _range.start.subtract(
                                              const Duration(days: 1),
                                            ),
                                          ),
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  Expanded(
                                    child: TextButton(
                                      key: const Key('history-select-date'),
                                      onPressed: _locked ? null : _pickRange,
                                      child: Text(
                                        '${MedicationHistoryDates.format(_range.start)} (${(widget.isEnglish ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] : const ['월', '화', '수', '목', '금', '토', '일'])[_range.start.weekday - 1]})',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    key: const Key('history-next-day'),
                                    tooltip: tr('다음 날짜', 'Next day'),
                                    onPressed:
                                        _locked ||
                                            !_range.start.isBefore(
                                              _control.today,
                                            )
                                        ? null
                                        : () => _selectDay(
                                            _range.start.add(
                                              const Duration(days: 1),
                                            ),
                                          ),
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              if (_control.loading)
                                const Padding(
                                  padding: EdgeInsets.all(32),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (_control.error != null) ...[
                                Text(
                                  _failureText(
                                    _control.error!,
                                    widget.isEnglish,
                                  ),
                                  key: const Key('history-load-error'),
                                  style: const TextStyle(
                                    color: MedBuddyColors.danger,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (!_control.sessionInvalidated)
                                  OutlinedButton.icon(
                                    onPressed: _locked ? null : _load,
                                    icon: const Icon(Icons.refresh),
                                    label: Text(tr('다시 시도', 'Retry')),
                                  ),
                              ] else if (snapshot != null) ...[
                                Row(
                                  key: const Key('history-status-summary'),
                                  children: [
                                    Expanded(
                                      child: Wrap(
                                        spacing: 16,
                                        runSpacing: 8,
                                        children: [
                                          for (final status
                                              in MedicationHistoryStatus.values)
                                            Text(
                                              '${status.label(widget.isEnglish)} ${snapshot.count(status)}',
                                              style: TextStyle(
                                                color: _statusColor(status),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: tr(
                                        '복약 기록 안내',
                                        'About medication records',
                                      ),
                                      onPressed: _locked
                                          ? null
                                          : _showRecordNotice,
                                      icon: const Icon(Icons.info_outline),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                if (snapshot.items.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 24,
                                    ),
                                    child: Text(
                                      tr(
                                        '이 날짜에는 복약 일정이나 기록이 없어요.',
                                        'No scheduled doses or records on this date.',
                                      ),
                                    ),
                                  ),
                                for (final slot in const [
                                  'morning',
                                  'lunch',
                                  'evening',
                                  'bedtime',
                                  'as_needed',
                                ])
                                  if (snapshot.items.any(
                                    (entry) => slot == 'as_needed'
                                        ? entry.isAsNeeded
                                        : entry.slotKey == slot,
                                  ))
                                    _slotCard(
                                      slot,
                                      snapshot.items
                                          .where(
                                            (entry) => slot == 'as_needed'
                                                ? entry.isAsNeeded
                                                : entry.slotKey == slot,
                                          )
                                          .toList(),
                                    ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  // 공유된 기간을 다른 날짜로 바꾸지 않고 날짜·시간대별 최신 기록을 보여준다.
  List<Widget> _sharedPeriodBody(MedicationHistorySnapshot? snapshot) {
    final days =
        snapshot?.items.map((entry) => entry.scheduleDate).toSet().toList()
          ?..sort((a, b) => b.compareTo(a));
    return [
      Text(
        _range.label,
        key: const Key('history-shared-period'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      if (_control.loading)
        const LinearProgressIndicator()
      else if (_control.error != null) ...[
        Text(
          _failureText(_control.error!, widget.isEnglish),
          key: const Key('history-load-error'),
          style: const TextStyle(color: MedBuddyColors.danger),
        ),
        if (!_control.sessionInvalidated)
          OutlinedButton.icon(
            onPressed: _locked ? null : _load,
            icon: const Icon(Icons.refresh),
            label: Text(tr('다시 시도', 'Retry')),
          ),
      ] else if (snapshot != null) ...[
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final status in MedicationHistoryStatus.values)
                    Text(
                      '${status.label(widget.isEnglish)} ${snapshot.count(status)}',
                      style: TextStyle(
                        color: _statusColor(status),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: _locked ? null : _showRecordNotice,
              tooltip: tr('복약 기록 안내', 'About medication records'),
              icon: const Icon(Icons.info_outline),
            ),
          ],
        ),
        if (snapshot.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              tr(
                '이 기간에는 복약 일정이나 기록이 없어요.',
                'No scheduled doses or records in this period.',
              ),
            ),
          ),
        for (final day in days ?? <DateTime>[]) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              MedicationHistoryDates.format(day),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          for (final slot in const [
            'morning',
            'lunch',
            'evening',
            'bedtime',
            'as_needed',
          ])
            if (snapshot.items.any(
              (entry) =>
                  entry.scheduleDate == day &&
                  (slot == 'as_needed'
                      ? entry.isAsNeeded
                      : entry.slotKey == slot),
            ))
              _slotCard(
                slot,
                snapshot.items
                    .where(
                      (entry) =>
                          entry.scheduleDate == day &&
                          (slot == 'as_needed'
                              ? entry.isAsNeeded
                              : entry.slotKey == slot),
                    )
                    .toList(),
              ),
        ],
      ],
    ];
  }

  // 함수역할: 달력, 불러오는 중·실패 상태, 날짜를 눌러 보라는 안내를 차례로 놓는다.
  List<Widget> _monthBody() => [
    MedicationHistoryMonthCalendar(
      month: _month,
      today: _control.today,
      selected: _range.start,
      summaries: _monthSnapshot == null
          ? const {}
          : MedicationHistoryDaySummary.fromSnapshot(_monthSnapshot!),
      isEnglish: widget.isEnglish,
      enabled: !_locked,
      onDaySelected: (day) => unawaited(_openDay(day)),
      onMonthChanged: (month) => unawaited(_changeMonth(month)),
    ),
    const SizedBox(height: 12),
    if (_control.loading)
      const LinearProgressIndicator(key: Key('history-month-loading'))
    else if (_monthFailed) ...[
      Text(
        tr('이 달의 기록을 불러오지 못했어요.', 'Could not load the records of this month.'),
        key: const Key('history-month-error'),
        style: const TextStyle(color: MedBuddyColors.danger),
      ),
      const SizedBox(height: 8),
      if (!_control.sessionInvalidated)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _locked ? null : _loadMonth,
            icon: const Icon(Icons.refresh),
            label: Text(tr('다시 시도', 'Retry')),
          ),
        ),
    ],
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: Text(
            tr(
              '날짜를 누르면 그날의 자세한 기록을 볼 수 있어요. 기록이 없다고 복용하지 않았다는 뜻은 아니에요.',
              'Tap a date to see its records. A missing record does not mean a missed dose.',
            ),
            style: const TextStyle(color: MedBuddyColors.textMuted),
          ),
        ),
        IconButton(
          tooltip: tr('복약 기록 안내', 'About medication records'),
          onPressed: _locked ? null : _showRecordNotice,
          icon: const Icon(Icons.info_outline),
        ),
      ],
    ),
  ];

  // 일정 화면과 같은 진행률·시간대 색상을 사용하되 실제 복용의 증명으로 표시하지 않는다.
  // 필요시 복용은 정해진 횟수가 없으므로 일정 화면처럼 현황의 분모·분자에 넣지 않는다.
  Widget _progress(MedicationHistorySnapshot snapshot) {
    final scheduled = snapshot.items.where((item) => !item.isAsNeeded);
    final total = scheduled.length;
    final taken = scheduled
        .where((item) => item.status == MedicationHistoryStatus.taken)
        .length;
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: MedBuddyRadii.control,
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('복용 기록 현황', 'Record summary'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$taken/$total',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: total == 0 ? 0 : taken / total,
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            backgroundColor: Colors.white.withValues(alpha: 0.22),
          ),
        ],
      ),
    );
  }

  // 같은 시간대의 기록을 한 카드 안에 모으고 이력 화면에는 알림 조작을 노출하지 않는다.
  Widget _slotCard(String slot, List<MedicationHistoryEntry> entries) {
    final style = MedBuddySlotStyle.of(slot);
    final taken = entries
        .where((entry) => entry.status == MedicationHistoryStatus.taken)
        .length;
    return Container(
      key: ValueKey('history-slot-$slot'),
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: MedBuddyColors.surface,
        borderRadius: MedBuddyRadii.card,
        border: Border.all(color: MedBuddyColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: style.tint,
              border: Border(left: BorderSide(color: style.color, width: 4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: style.color,
                    borderRadius: MedBuddyRadii.control,
                  ),
                  child: Icon(
                    slot == 'as_needed'
                        ? Icons.medication_outlined
                        : style.icon,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entries.first.slotLabel(widget.isEnglish),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$taken/${entries.length}',
                  style: TextStyle(
                    color: style.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: MedBuddyColors.cardBorder),
            _entryTile(entries[i]),
          ],
        ],
      ),
    );
  }

  // 함수역할: 한 보고의 예정일·실제 시각·기록 시각·사유를 구분하고 허용된 경우 정정 명령을 제공한다.
  Widget _entryTile(MedicationHistoryEntry entry) => Container(
    key: ValueKey('history-entry-${entry.key}'),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.itemName,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      decoration: entry.status == MedicationHistoryStatus.taken
                          ? TextDecoration.lineThrough
                          : null,
                      color: entry.status == MedicationHistoryStatus.taken
                          ? MedBuddyColors.textMuted
                          : MedBuddyColors.textStrong,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.status.label(widget.isEnglish),
                    style: TextStyle(
                      color: _statusColor(entry.status),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (!_readOnly)
              IconButton(
                tooltip: tr('기록 수정', 'Edit record'),
                onPressed: _locked ? null : () => _edit(entry),
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        if (entry.status == MedicationHistoryStatus.taken ||
            entry.recordedAt != null ||
            entry.reason.isNotEmpty)
          const SizedBox(height: 8),
        if (entry.status == MedicationHistoryStatus.taken)
          Text(
            '${tr('실제 복용', 'Actual taken')}: ${entry.actualTakenAt == null ? tr('시각 미입력', 'Time not provided') : MedicationHistoryDates.timestamp(entry.actualTakenAt)}',
          ),
        if (entry.recordedAt != null)
          Text(
            '${tr('기록 시각', 'Recorded at')}: ${MedicationHistoryDates.timestamp(entry.recordedAt)}',
          ),
        if (entry.reason.isNotEmpty)
          Text('${tr('이유', 'Reason')}: ${entry.reason}'),
      ],
    ),
  );
}

// 대화 상대와 기간을 확인한 뒤에만 전송하며 실패한 전송은 같은 요청으로 재시도한다.
class _HistoryChatShareDialog extends StatefulWidget {
  const _HistoryChatShareDialog({
    required this.history,
    required this.share,
    required this.range,
    required this.isEnglish,
  });
  final MedicationHistoryControl history;
  final ShareMedicationHistory share;
  final MedicationHistoryRange range;
  final bool isEnglish;

  @override
  State<_HistoryChatShareDialog> createState() =>
      _HistoryChatShareDialogState();
}

class _HistoryChatShareDialogState extends State<_HistoryChatShareDialog> {
  List<PatientCaregiverLink> _recipients = const [];
  int? _selected;
  bool _loading = true;
  bool _sending = false;
  bool _loadFailed = false;
  bool _sendFailed = false;
  String tr(String ko, String en) => widget.isEnglish ? en : ko;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _recipients = const [];
      _selected = null;
    });
    try {
      final links = await widget.share.loadRecipients();
      if (!mounted) return;
      setState(() => _recipients = links);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final selected = _selected;
    if (selected == null || _sending || _loading) return;
    final peer = widget.share.peerName(
      _recipients.firstWhere((link) => link.linkId == selected),
    );
    setState(() {
      _sending = true;
      _sendFailed = false;
    });
    try {
      await widget.share.send(linkId: selected, range: widget.range);
      if (mounted) Navigator.pop(context, peer);
    } catch (_) {
      if (mounted) setState(() => _sendFailed = true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.history,
    builder: (context, _) => widget.history.sessionInvalidated
        ? _sessionEndedDialog(context, widget.isEnglish)
        : PopScope(
            canPop: !_sending,
            child: AlertDialog(
              title: Text(tr('채팅으로 공유', 'Share in chat')),
              scrollable: true,
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.range.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      if (_loading)
                        const LinearProgressIndicator()
                      else if (_loadFailed) ...[
                        Text(
                          tr(
                            '대화 상대를 확인하지 못했어요.',
                            'Could not verify chat recipients.',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: Text(tr('다시 조회', 'Retry')),
                        ),
                      ] else if (_recipients.isEmpty)
                        Text(
                          tr(
                            '이 환자와 연결된 대화 상대가 없어요.',
                            'There are no connected chats for this patient.',
                          ),
                        )
                      else
                        RadioGroup<int>(
                          groupValue: _selected,
                          onChanged: (value) {
                            if (!_sending) {
                              setState(() {
                                _selected = value;
                                _sendFailed = false;
                              });
                            }
                          },
                          child: Column(
                            children: [
                              for (final link in _recipients)
                                RadioListTile<int>(
                                  key: ValueKey(
                                    'history-share-recipient-${link.linkId}',
                                  ),
                                  value: link.linkId!,
                                  enabled: !_sending,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(widget.share.peerName(link)),
                                ),
                            ],
                          ),
                        ),
                      if (_recipients.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          tr(
                            '선택한 상대에게 복약 기록 요약을 보냅니다.',
                            'The selected person will receive a medication record summary.',
                          ),
                        ),
                      ],
                      if (_sending)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                      if (_sendFailed)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            tr(
                              '전송 결과를 확인하지 못했어요. 연결 상태와 환자·보호자 연동을 확인한 뒤 다시 시도해 주세요.',
                              'Could not confirm delivery. Check your connection and patient-caregiver link, then retry.',
                            ),
                            key: const Key('history-chat-share-error'),
                            style: const TextStyle(
                              color: MedBuddyColors.danger,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _sending ? null : () => Navigator.pop(context),
                  child: Text(tr('취소', 'Cancel')),
                ),
                FilledButton.icon(
                  key: const Key('history-chat-send'),
                  onPressed: _selected == null || _loading || _sending
                      ? null
                      : _send,
                  icon: Icon(_sendFailed ? Icons.refresh : Icons.send_outlined),
                  label: Text(
                    _sendFailed
                        ? tr('다시 전송', 'Retry sending')
                        : tr('전송', 'Send'),
                  ),
                ),
              ],
            ),
          ),
  );
}

// 일정에서는 선택한 필요시 약의 새 복용만, 기록에서는 기존 보고의 정정만 연다.
Future<bool> recordAsNeededDose({
  required BuildContext context,
  required MedicationHistoryControl control,
  required MedicationHistoryMedication medication,
  required bool isEnglish,
  MedicationHistoryChange? pendingChange,
  ValueChanged<MedicationHistoryChange?>? onPendingChanged,
}) async {
  control.ensureSession();
  final snapshot = control.snapshot;
  if (pendingChange != null &&
      (pendingChange.entry.medicationId != medication.id ||
          !pendingChange.entry.isAsNeeded)) {
    return false;
  }
  if (control.readOnly ||
      control.busy ||
      snapshot == null ||
      (pendingChange == null && snapshot.range.end != control.today) ||
      (pendingChange == null &&
          !snapshot.medications.any(
            (item) =>
                item.id == medication.id &&
                item.dosingMode == 'as_needed' &&
                item.canRecordAsNeeded,
          ))) {
    return false;
  }
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _MedicationHistoryEditor(
          control: control,
          snapshot: snapshot,
          entry: null,
          newMedication: medication,
          pendingChange: pendingChange,
          onPendingChanged: onPendingChanged,
          isEnglish: isEnglish,
        ),
      ) ==
      true;
}

// 클래스명: _MedicationHistoryEditor
// 역할: 하나의 기존 기록 또는 새 필요시 복용 이벤트를 편집하는 대화상자이다.
class _MedicationHistoryEditor extends StatefulWidget {
  // 함수역할: 동일 환자 제어 객체와 조회 스냅샷·선택 보고를 편집기에 전달한다.
  const _MedicationHistoryEditor({
    required this.control,
    required this.snapshot,
    required this.entry,
    required this.isEnglish,
    this.newMedication,
    this.pendingChange,
    this.onPendingChanged,
  });
  final MedicationHistoryControl control;
  final MedicationHistorySnapshot snapshot;
  final MedicationHistoryEntry? entry;
  final bool isEnglish;
  final MedicationHistoryMedication? newMedication;
  final MedicationHistoryChange? pendingChange;
  final ValueChanged<MedicationHistoryChange?>? onPendingChanged;

  // 함수역할: 입력값·재시도 의도·충돌 상태를 보존할 편집 상태를 만든다.
  @override
  State<_MedicationHistoryEditor> createState() =>
      _MedicationHistoryEditorState();
}

// 클래스명: _MedicationHistoryEditorState
// 역할: 실제 날짜·시각과 사유를 검증하고 응답 유실 때 같은 작업 ID를 재사용한다.
class _MedicationHistoryEditorState extends State<_MedicationHistoryEditor> {
  late MedicationHistoryStatus _status;
  late DateTime _scheduleDate;
  late DateTime _actualDate;
  late TimeOfDay _actualTime;
  late final TextEditingController _reason;
  late final String _newSlotKey;
  int? _medicationId;
  MedicationHistoryChange? _pending;
  Object? _error;
  bool _submitting = false;
  bool _conflict = false;

  // 함수역할: 편집기의 선택 언어 문구를 반환한다.
  String tr(String ko, String en) => widget.isEnglish ? en : ko;
  // 함수역할: 확인·전송 또는 세션 무효화 중 저장을 차단할지 반환한다.
  bool get _locked => _submitting || widget.control.sessionInvalidated;
  // 함수역할: 미확인 전송 의도가 있으면 입력 변경도 막아 동일 내용 재시도를 보장한다.
  bool get _fieldsLocked => _locked || _pending != null || _conflict;
  // 함수역할: 편집 가능한 입력 검증 오류만 지우며 미확인 전송·버전 충돌 오류는 보존한다.
  void _clearEditableValidationError() {
    final error = _error;
    if (!_fieldsLocked &&
        (error is FormatException ||
            (error is ApiRequestException && error.statusCode == 422))) {
      _error = null;
    }
  }

  // 함수역할: 서버가 필요시 복용으로 구분한 약만 새 이벤트의 대상으로 반환한다.
  List<MedicationHistoryMedication> get _prnMedications => widget
      .snapshot
      .medications
      .where((medication) => medication.dosingMode == 'as_needed')
      .toList();

  // 함수역할: 기존 보고의 실제 시각을 보존하고 새 필요시 복용에는 독립 UUID 시간대를 배정한다.
  @override
  void initState() {
    super.initState();
    final entry = widget.entry ?? widget.pendingChange?.entry;
    _pending = widget.pendingChange;
    _status =
        widget.pendingChange?.status ??
        entry?.status ??
        MedicationHistoryStatus.taken;
    _scheduleDate = entry?.scheduleDate ?? widget.snapshot.range.end;
    _medicationId = entry?.medicationId ?? widget.newMedication?.id;
    final now = MedicationHistoryDates.wallTime(widget.control.now);
    final actualTakenAt =
        widget.pendingChange?.actualTakenAt ?? entry?.actualTakenAt;
    final time = actualTakenAt == null
        ? null
        : MedicationHistoryDates.wallTime(actualTakenAt);
    _actualDate = time == null
        ? _scheduleDate
        : MedicationHistoryDates.day(time);
    _actualTime = TimeOfDay(
      hour: time?.hour ?? now.hour,
      minute: time?.minute ?? now.minute,
    );
    _reason = TextEditingController(text: entry?.reason ?? '');
    _newSlotKey = 'as_needed:${MedicationHistoryControl.newOperationId()}';
  }

  // 함수역할: 사용자가 입력한 사유의 텍스트 제어기를 해제한다.
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  // 함수역할: 실제 복용 날짜는 최근 90일, 새 필요시 기록 날짜는 조회 기간 안에서 고른다.
  Future<void> _pickDate({required bool actual}) async {
    if (_fieldsLocked) return;
    final selected = await showDatePicker(
      context: context,
      locale: Locale(widget.isEnglish ? 'en' : 'ko'),
      initialDate: actual ? _actualDate : _scheduleDate,
      firstDate: actual
          ? widget.control.today.subtract(const Duration(days: 89))
          : widget.snapshot.range.start,
      lastDate: actual ? widget.control.today : widget.snapshot.range.end,
      currentDate: widget.control.today,
      helpText: actual
          ? tr('실제 복용 날짜', 'Actual taken date')
          : tr('기록할 날짜', 'Record date'),
    );
    if (!mounted || selected == null || _fieldsLocked) return;
    final selectedDay = MedicationHistoryDates.day(selected);
    if (selectedDay == (actual ? _actualDate : _scheduleDate)) return;
    setState(() {
      if (actual) {
        _actualDate = selectedDay;
      } else {
        _scheduleDate = selectedDay;
        _actualDate = _scheduleDate;
      }
      _clearEditableValidationError();
    });
  }

  // 함수역할: 한국 시간 기준 실제 복용 시·분을 고르고 시각이 미래인지는 저장 전 검증한다.
  Future<void> _pickTime() async {
    if (_fieldsLocked) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _actualTime,
      helpText: tr('실제 복용 시각 (한국 시간)', 'Actual taken time (Korea)'),
    );
    if (!mounted || time == null || _fieldsLocked) return;
    if (time == _actualTime) return;
    setState(() {
      _actualTime = time;
      _clearEditableValidationError();
    });
  }

  // 함수역할: 현재 입력을 새 작업 UUID로 고정하고 기존 예정일·이벤트 키는 보존한다.
  MedicationHistoryChange _buildChange() {
    final medication = _prnMedications
        .where((medication) => medication.id == _medicationId)
        .firstOrNull;
    final entry =
        widget.entry ??
        MedicationHistoryEntry(
          medicationId: medication!.id,
          itemName: medication.itemName,
          scheduleDate: _scheduleDate,
          slotKey: _newSlotKey,
          status: MedicationHistoryStatus.unrecorded,
          revision: 0,
          dosingMode: 'as_needed',
        );
    return MedicationHistoryChange(
      entry: entry,
      status: _status,
      operationId: MedicationHistoryControl.newOperationId(),
      actualTakenAt: _status == MedicationHistoryStatus.taken
          ? MedicationHistoryDates.instant(
              _actualDate,
              _actualTime.hour,
              _actualTime.minute,
            )
          : null,
      reason: _status == MedicationHistoryStatus.skipped
          ? _reason.text.trim()
          : '',
    );
  }

  // 함수역할: 입력 검증과 확인 후 저장하며 충돌은 새 조회, 응답 유실은 같은 의도 재시도로 안내한다.
  Future<void> _save() async {
    if (_locked || _conflict) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      widget.control.ensureSession();
      if (widget.entry == null &&
          _pending == null &&
          _scheduleDate != widget.control.today) {
        throw const FormatException('Reopen the schedule for the current day.');
      }
      final change = _pending ?? _buildChange();
      change.validate(widget.control.now);
      if (_pending == null && widget.entry != null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AnimatedBuilder(
            animation: widget.control,
            builder: (context, _) => widget.control.sessionInvalidated
                ? _sessionEndedDialog(context, widget.isEnglish)
                : AlertDialog(
                    title: Text(tr('이 내용으로 기록할까요?', 'Save this record?')),
                    content: SingleChildScrollView(
                      child: Text(
                        '${change.entry.itemName}\n${MedicationHistoryDates.format(change.entry.scheduleDate)} · '
                        '${change.entry.slotLabel(widget.isEnglish)}\n${change.status.label(widget.isEnglish)}'
                        '${change.actualTakenAt == null ? '' : '\n${tr('실제 복용', 'Actual taken')}: ${MedicationHistoryDates.timestamp(change.actualTakenAt)}'}'
                        '${change.reason.isEmpty ? '' : '\n${tr('이유', 'Reason')}: ${change.reason}'}\n\n'
                        '${tr('이 기록은 실제 복용의 증명이 아닌 사용자 입력입니다. 복용 여부를 정정하며 약의 처방이나 알림 시간은 변경하지 않습니다.', 'This is a self-reported record, not proof of ingestion. It corrects the record, not the prescription or reminder times.')}',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr('취소', 'Cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(tr('저장', 'Save')),
                      ),
                    ],
                  ),
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      _pending = change;
      if (widget.entry == null) widget.onPendingChanged?.call(change);
      await widget.control.save(change);
      if (widget.entry == null) widget.onPendingChanged?.call(null);
      if (mounted) {
        setState(() => _submitting = false);
        Navigator.pop(context, true);
      }
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure;
        if (failure is ApiRequestException && failure.statusCode == 409) {
          _conflict = true;
          if (widget.entry == null) widget.onPendingChanged?.call(null);
        }
        // 명시적인 입력 거절만 수정 가능하게 풀고 응답 유실은 같은 작업 ID로 재시도한다.
        if (failure is ApiRequestException && failure.statusCode == 422) {
          _pending = null;
          if (widget.entry == null) widget.onPendingChanged?.call(null);
        }
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // 함수역할: 세 상태와 실제 날짜·시각·사유를 편집하고 세션 변경 시 민감한 내용을 숨긴다.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.control,
    builder: (context, _) => widget.control.sessionInvalidated
        ? _sessionEndedDialog(context, widget.isEnglish)
        : PopScope(
            canPop: !_submitting,
            child: AlertDialog(
              title: Text(
                widget.entry == null
                    ? tr('복용 확인', 'Confirm dose')
                    : tr('복약 기록 수정', 'Edit medication record'),
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.entry != null) ...[
                        Text(
                          widget.entry!.itemName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${widget.entry!.isAsNeeded ? tr('기록일', 'Record date') : tr('예정일', 'Scheduled date')} ${MedicationHistoryDates.format(_scheduleDate)} · ${widget.entry!.slotLabel(widget.isEnglish)}',
                        ),
                      ] else ...[
                        Text(
                          widget.newMedication!.itemName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (widget.newMedication!.dosage.isNotEmpty)
                          Text(widget.newMedication!.dosage),
                      ],
                      const SizedBox(height: 12),
                      if (widget.entry != null)
                        RadioGroup<MedicationHistoryStatus>(
                          groupValue: _status,
                          onChanged: (value) {
                            if (!_fieldsLocked &&
                                value != null &&
                                value != _status) {
                              setState(() {
                                _status = value;
                                _clearEditableValidationError();
                              });
                            }
                          },
                          child: Column(
                            children: [
                              // 필요시 복용에는 건너뛸 예정 복용이 없으므로 건너뜀은 이미 그렇게 저장된
                              // 기록에만 보이고, 미기록은 잘못 누른 기록의 취소로 안내한다.
                              for (final status
                                  in MedicationHistoryStatus.values)
                                if (!widget.entry!.isAsNeeded ||
                                    status != MedicationHistoryStatus.skipped ||
                                    widget.entry!.status ==
                                        MedicationHistoryStatus.skipped)
                                  RadioListTile<MedicationHistoryStatus>(
                                    value: status,
                                    enabled: !_fieldsLocked,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      widget.entry!.isAsNeeded &&
                                              status ==
                                                  MedicationHistoryStatus
                                                      .unrecorded
                                          ? tr(
                                              '기록 취소 (잘못 기록함)',
                                              'Cancel record (recorded by mistake)',
                                            )
                                          : status.label(widget.isEnglish),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      if (_status == MedicationHistoryStatus.taken) ...[
                        const SizedBox(height: 8),
                        Text(
                          tr('실제 복용 시각 (한국 시간)', 'Actual taken time (Korea)'),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _fieldsLocked || widget.entry == null
                                  ? null
                                  : () => _pickDate(actual: true),
                              icon: const Icon(Icons.calendar_today_outlined),
                              label: Text(
                                MedicationHistoryDates.format(_actualDate),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _fieldsLocked ? null : _pickTime,
                              icon: const Icon(Icons.schedule),
                              label: Text(
                                '${_actualTime.hour.toString().padLeft(2, '0')}:${_actualTime.minute.toString().padLeft(2, '0')}',
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_status == MedicationHistoryStatus.skipped) ...[
                        Text(
                          widget.entry?.isAsNeeded == true
                              ? tr(
                                  '건너뛴 기록은 복용 완료로 처리되지 않습니다.',
                                  'Skipped doses are not marked as taken.',
                                )
                              : tr(
                                  '건너뛴 기록은 복용 완료로 처리되지 않으며 기존 복약·미복약 알림은 유지됩니다.',
                                  'Skipped doses are not marked as taken. Existing dose reminders and missed-dose alerts remain active.',
                                ),
                          key: const Key('history-skipped-notice'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('history-skip-reason'),
                          controller: _reason,
                          enabled: !_fieldsLocked,
                          maxLength: 200,
                          minLines: 1,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: tr(
                              '건너뛴 이유 (선택)',
                              'Skip reason (optional)',
                            ),
                          ),
                        ),
                      ],
                      if (widget.entry?.recordedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '${tr('이전 기록 시각', 'Previously recorded at')}: '
                            '${MedicationHistoryDates.timestamp(widget.entry!.recordedAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (_error != null || widget.control.sessionInvalidated)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _failureText(
                              widget.control.sessionInvalidated
                                  ? const MedicationHistorySessionChanged()
                                  : _error!,
                              widget.isEnglish,
                            ),
                            key: const Key('history-save-error'),
                            style: const TextStyle(
                              color: MedBuddyColors.danger,
                            ),
                          ),
                        ),
                      if (_pending != null && !_submitting && !_conflict)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            tr(
                              '입력한 내용 그대로 재시도합니다. 닫으면 서버 기록을 다시 조회합니다.',
                              'Retry sends the same record. Closing reloads the server history.',
                            ),
                          ),
                        ),
                      if (widget.control.saving)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.pop(context, false),
                  child: Text(
                    _conflict
                        ? tr('닫고 새로고침', 'Close and refresh')
                        : tr('닫기', 'Close'),
                  ),
                ),
                if (!_conflict)
                  FilledButton.icon(
                    key: const Key('history-save'),
                    onPressed: _locked || _medicationId == null ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      _pending != null
                          ? tr('같은 기록 재시도', 'Retry record')
                          : widget.entry == null
                          ? tr('복용했어요', 'Taken')
                          : tr('기록 저장', 'Save record'),
                    ),
                  ),
              ],
            ),
          ),
  );
}

// 함수역할: 세션이 바뀌면 열려 있는 대화상자에서도 이전 환자의 내용을 숨긴다.
Widget _sessionEndedDialog(BuildContext context, bool english) => AlertDialog(
  title: Text(english ? 'Session changed' : '로그인 정보 변경'),
  content: Text(_failureText(const MedicationHistorySessionChanged(), english)),
  actions: [
    TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text(english ? 'Close' : '닫기'),
    ),
  ],
);

// 함수역할: 사용자 보고 상태에 대응하는 앱의 의미 색상을 반환한다.
Color _statusColor(MedicationHistoryStatus status) => switch (status) {
  MedicationHistoryStatus.taken => MedBuddyColors.primary,
  MedicationHistoryStatus.skipped => MedBuddyColors.reminderAccent,
  MedicationHistoryStatus.unrecorded => MedBuddyColors.textMuted,
};

// 함수역할: 내부 서버 응답을 그대로 노출하지 않고 권한·충돌·입력·연결 오류를 구분해 설명한다.
String _failureText(Object failure, bool english) {
  // 함수역할: 오류 문구의 한국어·영어 표현 중 요청 언어를 선택한다.
  String tr(String ko, String en) => english ? en : ko;
  if (failure is MedicationHistorySessionChanged) {
    return tr(
      '로그인 정보가 바뀌었어요. 화면을 닫고 다시 열어 주세요.',
      'The session changed. Close this screen and open it again.',
    );
  }
  if (failure is FormatException) {
    return tr(
      '날짜·실제 복용 시각 또는 응답 내용을 확인하지 못했어요. 미래 시각은 기록할 수 없습니다.',
      'The date, actual taken time or response could not be validated. Future times cannot be recorded.',
    );
  }
  if (failure is ApiRequestException) {
    if (failure.statusCode == 409) {
      return tr(
        '다른 기기에서 기록이 바뀌었어요. 닫고 새로고침한 뒤 다시 확인해 주세요.',
        'The record changed on another device. Close, refresh, and review it again.',
      );
    }
    if (failure.statusCode == 401 || failure.statusCode == 403) {
      return tr(
        '로그인 또는 환자 조회 권한을 확인해 주세요.',
        'Check your sign-in and permission to view this patient.',
      );
    }
    if (failure.statusCode == 404) {
      return tr(
        '이 기록을 찾을 수 없거나 서버가 기록 관리를 아직 지원하지 않아요.',
        'This record was not found, or the server does not yet support history.',
      );
    }
    if (failure.statusCode == 422) {
      return tr(
        '해당 날짜와 복용법에 맞는 기록인지 확인해 주세요.',
        'Check that the record matches the date and dosing instructions.',
      );
    }
  }
  return tr(
    '서버에서 처리 결과를 확인하지 못했어요. 연결을 확인하고 다시 시도해 주세요.',
    'The result could not be confirmed with the server. Check your connection and try again.',
  );
}
