// 파일명: medication_history_ui_boundary.dart
// 역할: 환자·보호자의 주간·월간·기간별 복약 이력, 정정 확인, 개인정보 안내 후 텍스트 공유를 제공한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controls/medication_history_control.dart';
import '../controls/share_medication_history_control.dart';
import '../entities/medication_history_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/patient_caregiver_link_entity.dart';
import '../widgets/medication_history_month_calendar.dart';
import '../widgets/medication_history_charts.dart';
import '../entities/medication_history_export.dart';
import '../services/api_response_parser.dart';
import '../theme/medbuddy_theme.dart';
import '../widgets/medication_entry_fields.dart';
import '../widgets/medbuddy_page_header.dart';
import '../widgets/keep_words_text.dart';

// 클래스명: _HistoryShareDestination
// 역할: 복약 기록을 공유할 목적지 구분.
// 주요 책임: 외부 앱 텍스트 공유와 연동 채팅 공유를 구별한다.
// 속성: external/chat: 두 공유 목적지 값.
enum _HistoryShareDestination { external, chat }

// 클래스명: _HistoryPeriod
// 역할: 이력 집계 기간의 선택 모드.
// 주요 책임: 주간·월간과 직접 지정 기간을 구별한다.
// 속성: week/month/custom: 기간 모드 값.
enum _HistoryPeriod { week, month, custom }

// 클래스명: MedicationHistoryUI
// 역할: 환자 범위와 읽기 권한을 전달받는 복약 이력 화면.
// 주요 책임: 기간 조회·정정·공유를 연결하고 채팅에서 연 기간은 읽기 전용으로 표시한다.
// 속성: patientHash/currentUserHash (String/String?): 조회·현재 계정; control/chatShareControl: 외부 소유 제어기; sharedRange (MedicationHistoryRange?): 공유 기간; readOnly/isActive (bool): 권한·가시성; recordChanges (Listenable?): 변경 신호; chatLinkId (int?): 공유 대상.
class MedicationHistoryUI extends StatefulWidget {
  // 함수이름: MedicationHistoryUI
  // 함수역할: 조회 환자·권한·공유 범위를 고정하고 주입한 제어기의 소유권은 부모에게 남긴다.
  // 매개변수: key (Key?): 키; patientHash/currentUserHash (String/String?): 계정; readOnly/isEnglish/initiallyShowExport/showBackButton/isActive (bool): 화면 옵션; onChanged (FutureOr<void> Function()? ): 갱신; control/chatShareControl: 조회·공유 제어기; sharedRange (MedicationHistoryRange?): 범위; recordChanges (Listenable?): 변경; chatLinkId (int?): 대상; onChatShared (VoidCallback?): 완료 통지.
  // 반환값: 새 MedicationHistoryUI.
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
    this.showBackButton = true,
    this.isActive = true,
    this.recordChanges,
    this.chatLinkId,
    this.onChatShared,
  });

  final String patientHash;
  final bool readOnly;
  final bool isEnglish;
  final FutureOr<void> Function()? onChanged;
  final MedicationHistoryControl? control;
  final String? currentUserHash;
  final ShareMedicationHistory? chatShareControl;
  // 채팅에서 들어오면 서버가 확인한 현재 연동만 공유 대상으로 표시한다.
  final int? chatLinkId;
  final VoidCallback? onChatShared;
  // 채팅에서 연 상세 화면은 공유 기간의 최신 자료만 읽기 전용으로 조회한다.
  final MedicationHistoryRange? sharedRange;
  // 기능 검색에서 공유를 선택해도 전송은 하지 않고 기존 기간·대상 확인창만 연다.
  final bool initiallyShowExport;
  final bool showBackButton;
  // 탭으로 유지되는 동안 숨겨지면 앱 복귀 때 서버 기록을 다시 읽지 않는다.
  final bool isActive;
  // 다른 화면에서 서버에 복용 기록이 저장됐다는 신호. 보이는 동안 받으면 다시 읽는다.
  final Listenable? recordChanges;

  // 함수이름: createState
  // 함수역할: 조회·정정·공유와 계정 변경을 관리할 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _MedicationHistoryUIState.
  @override
  State<MedicationHistoryUI> createState() => _MedicationHistoryUIState();
}

// 클래스명: _MedicationHistoryUIState
// 역할: 환자별 조회 범위와 비동기 작업의 수명을 관리한다.
// 주요 책임: 세션·제어기 변경 후 결과를 폐기하고 기록 변경 신호를 대화상자 종료 뒤 재조회한다.
// 속성: _control (MedicationHistoryControl): 조회; _range (MedicationHistoryRange): 범위; _ownsControl (bool): 소유권; _interactionActive/_exporting/_recordsChanged (bool): 작업·후속 조회; _period/_selectedDay: 기간·상세 날짜.
class _MedicationHistoryUIState extends State<MedicationHistoryUI>
    with WidgetsBindingObserver {
  static const _exportChannel = MethodChannel(medicationHistoryExportChannel);
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late MedicationHistoryControl _control;
  late MedicationHistoryRange _range;
  bool _ownsControl = false;
  ShareMedicationHistory? _chatShare;
  // 함수이름: _readOnly
  // 함수역할: 일반 읽기 전용 설정 또는 채팅 공유 범위로 열린 화면인지 확인한다.
  // 매개변수: 없음.
  // 반환값: 어느 조건이든 맞으면 true.
  bool get _readOnly => widget.readOnly || widget.sharedRange != null;
  bool _interactionActive = false;
  bool _exporting = false;
  // 조회·대화상자·공유 중에 기록이 바뀌었으면 끝난 뒤 한 번 다시 읽는다.
  bool _recordsChanged = false;
  _HistoryPeriod _period = _HistoryPeriod.week;
  late DateTime _anchor;
  late DateTime _selectedDay;
  late DateTime _lastSeenToday;
  late DateTime _customStart;
  late DateTime _customEnd;
  final _chartExpanded = <_HistoryPeriod, bool>{};
  final _detailsExpanded = <_HistoryPeriod, bool>{};

  // 함수이름: tr
  // 함수역할: 현재 이력 화면 언어에 맞는 문구를 선택한다.
  // 매개변수: ko/en (String): 두 언어 문구.
  // 반환값: 선택한 문구.
  String tr(String ko, String en) => widget.isEnglish ? en : ko;

  // Function Name: initState
  // Description: Registers lifecycle and record-change listeners, then binds the initial patient controller.
  // Parameters: None.
  // Returns: No return value; controller mismatch errors from binding propagate.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.recordChanges?.addListener(_onRecordsChanged);
    _bindControl();
  }

  // Function Name: _bindControl
  // Description: Validates injected controller identity/permissions, creates owned dependencies, resets dates and schedules an initial load.
  // Parameters: None.
  // Returns: No return value; throws ArgumentError for mismatched patient, sender or read-only scope.
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
    _period = _HistoryPeriod.week;
    _anchor = _selectedDay = _customEnd = _lastSeenToday = _control.today;
    _customStart = _control.today.subtract(const Duration(days: 6));
    _range = widget.sharedRange ?? _periodRange(_anchor, _period)!;
    _chartExpanded.clear();
    _detailsExpanded.clear();
    final bound = _control;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(bound, _control)) {
        unawaited(_loadInitial(bound));
      }
    });
  }

  // 함수이름: _loadInitial
  // 함수역할: 최초 조회가 끝나고 같은 세션이며 공유 가능한 화면일 때 요청된 내보내기 확인창을 연다.
  // 매개변수: bound (MedicationHistoryControl): 처음 연결한 조회 제어기.
  // 반환값: 조회·선택적 공유 확인 완료 Future<void>.
  Future<void> _loadInitial(MedicationHistoryControl bound) async {
    await _reload();
    if (!_isCurrent(bound) ||
        !widget.initiallyShowExport ||
        (_readOnly && widget.chatLinkId == null)) {
      return;
    }
    if (_control.snapshot != null) {
      await _export();
    }
  }

  // 함수이름: didUpdateWidget
  // 함수역할: 환자·권한·공유 대상이 바뀌면 이전 세션을 무효화하고 새 제어기를 연결하며 기록 변경 감시도 교체한다.
  // 매개변수: oldWidget (MedicationHistoryUI): 이전 화면 설정.
  // 반환값: 없음. 직접 소유한 이전 의존성만 해제한다.
  @override
  void didUpdateWidget(covariant MedicationHistoryUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recordChanges != widget.recordChanges) {
      oldWidget.recordChanges?.removeListener(_onRecordsChanged);
      widget.recordChanges?.addListener(_onRecordsChanged);
    }
    if (oldWidget.patientHash != widget.patientHash ||
        oldWidget.readOnly != widget.readOnly ||
        oldWidget.currentUserHash != widget.currentUserHash ||
        oldWidget.chatShareControl != widget.chatShareControl ||
        oldWidget.chatLinkId != widget.chatLinkId ||
        // 채팅 카드는 경로가 다시 그려질 때마다 같은 기간의 새 객체를 넘기므로 날짜로 비교한다.
        oldWidget.sharedRange?.start != widget.sharedRange?.start ||
        oldWidget.sharedRange?.end != widget.sharedRange?.end ||
        oldWidget.control != widget.control) {
      if (oldWidget.chatShareControl == null) _chatShare?.dispose();
      _control.invalidateSession();
      if (_ownsControl) _control.dispose();
      _interactionActive = false;
      _exporting = false;
      _bindControl();
    }
  }

  // Function Name: didChangeAppLifecycleState
  // Description: On visible-app resume, verifies the session and reloads unlocked history; a new Korean day advances noncustom periods to today.
  // Parameters: state (AppLifecycleState): new application state.
  // Returns: No return value; invalid sessions or active interactions do not reload.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !widget.isActive) return;
    try {
      _control.ensureSession();
    } catch (_) {
      return;
    }
    if (!_control.busy && !_interactionActive && !_exporting) {
      // 탭은 계속 유지되므로 날짜가 바뀐 뒤 돌아오면 주간·월간을 오늘로 옮긴다.
      final today = _control.today;
      if (today != _lastSeenToday) {
        _lastSeenToday = today;
        if (_period != _HistoryPeriod.custom) _anchor = _selectedDay = today;
      }
      unawaited(_reload());
    }
  }

  // Function Name: dispose
  // Description: Removes lifecycle and record listeners and disposes only dependencies created by this screen.
  // Parameters: None.
  // Returns: No return value.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.recordChanges?.removeListener(_onRecordsChanged);
    if (widget.chatShareControl == null) _chatShare?.dispose();
    if (_ownsControl) _control.dispose();
    super.dispose();
  }

  // Function Name: _load
  // Description: Loads the selected range and coalesces record changes arriving during lookup into another refresh.
  // Parameters: None.
  // Returns: Future<void>; lookup errors stay in controller state instead of escaping.
  Future<void> _load() async {
    _recordsChanged = false;
    try {
      await _control.load(_range);
    } catch (_) {
      // 서버·네트워크 오류는 제어 객체의 상태로 표시하고 이전 자료는 남기지 않는다.
    }
    if (_recordsChanged && mounted) _onRecordsChanged();
  }

  // Function Name: _onRecordsChanged
  // Description: Reloads visible valid-session history after a record change, deferring it while lookup, editing or export is active.
  // Parameters: None.
  // Returns: No return value; inactive or invalidated views ignore the signal.
  void _onRecordsChanged() {
    if (!widget.isActive || _control.sessionInvalidated) return;
    if (_control.busy || _interactionActive || _exporting) {
      _recordsChanged = true;
      return;
    }
    unawaited(_load());
  }

  // Function Name: _endInteraction
  // Description: Unlocks a completed interaction only for the still-bound controller and processes any deferred record refresh.
  // Parameters: control (MedicationHistoryControl): controller captured at interaction start.
  // Returns: No return value; disposed/rebound screens are ignored.
  void _endInteraction(MedicationHistoryControl control) {
    if (!mounted || !identical(control, _control)) return;
    setState(() {
      _interactionActive = false;
      _exporting = false;
    });
    if (_recordsChanged) _onRecordsChanged();
  }

  // 함수이름: _reload
  // 함수역할: 현재 주·월·지정 기간을 보관 한계에 맞추고 범위를 벗어난 상세 날짜를 끝날로 옮겨 다시 조회한다.
  // 매개변수: 없음.
  // 반환값: 조회 완료 Future<void>; 공유된 기간은 그대로 조회한다.
  Future<void> _reload() async {
    if (widget.sharedRange == null) {
      final earliest = MedicationHistoryDates.earliest(_control.today);
      final range = _period == _HistoryPeriod.custom
          ? MedicationHistoryRange(
              _range.start.isBefore(earliest) ? earliest : _range.start,
              _range.end.isBefore(earliest) ? earliest : _range.end,
            )
          : _periodRange(_anchor, _period);
      if (range != null) {
        _range = range;
        if (_period == _HistoryPeriod.custom) {
          _customStart = range.start;
          _customEnd = range.end;
        }
        if (!_range.contains(_selectedDay)) _selectedDay = _range.end;
      }
    }
    await _load();
  }

  // 함수이름: _periodRange
  // 함수역할: 선택 모드의 기간을 한국 오늘과 보관 가능한 최초 날짜 사이로 자른다.
  // 매개변수: anchor (DateTime): 주·월 기준일; period (_HistoryPeriod): 기간 모드.
  // 반환값: 조회 가능한 MedicationHistoryRange 또는 교집합이 없으면 null.
  MedicationHistoryRange? _periodRange(DateTime anchor, _HistoryPeriod period) {
    final today = _control.today;
    final earliest = MedicationHistoryDates.earliest(today);
    final start = switch (period) {
      _HistoryPeriod.week => anchor.subtract(
        Duration(days: anchor.weekday - 1),
      ),
      _HistoryPeriod.month => DateTime.utc(anchor.year, anchor.month),
      _HistoryPeriod.custom => _customStart,
    };
    final end = switch (period) {
      _HistoryPeriod.week => start.add(const Duration(days: 6)),
      _HistoryPeriod.month => DateTime.utc(anchor.year, anchor.month + 1, 0),
      _HistoryPeriod.custom => _customEnd,
    };
    final first = start.isBefore(earliest) ? earliest : start;
    final last = end.isAfter(today) ? today : end;
    return first.isAfter(last) ? null : MedicationHistoryRange(first, last);
  }

  // 함수이름: _changePeriod
  // 함수역할: 잠기지 않은 화면에서 기간 모드를 바꾸고 필요한 경우 상세 날짜를 보정한 뒤 조회한다.
  // 매개변수: period (_HistoryPeriod): 모드; anchor (DateTime?): 기준일, 생략하면 상세 날짜.
  // 반환값: 조회 완료 Future<void>; 허용 범위가 없으면 변경하지 않는다.
  Future<void> _changePeriod(_HistoryPeriod period, {DateTime? anchor}) async {
    if (_locked) return;
    final nextAnchor = anchor ?? _selectedDay;
    final range = _periodRange(nextAnchor, period);
    if (range == null) return;
    setState(() {
      _period = period;
      _anchor = nextAnchor;
      _range = range;
      if (period == _HistoryPeriod.custom) {
        _customStart = range.start;
        _customEnd = range.end;
      }
      if (!_range.contains(_selectedDay)) _selectedDay = _range.end;
    });
    await _load();
  }

  // 함수이름: _isCurrent
  // 함수역할: 화면이 살아 있고 같은 제어기이며 세션 검증도 통과하는지 확인한다.
  // 매개변수: control (MedicationHistoryControl): 작업 시작 시 제어기.
  // 반환값: 모두 유효하면 true; 세션 확인 예외는 false.
  bool _isCurrent(MedicationHistoryControl control) {
    if (!mounted || !identical(control, _control)) return false;
    try {
      control.ensureSession();
      return true;
    } catch (_) {
      return false;
    }
  }

  // 함수이름: _message
  // 함수역할: 살아 있는 이력 화면의 전용 메시지 영역에 안내를 6초 동안 표시한다.
  // 매개변수: message (String): 안내 문구.
  // 반환값: 없음.
  void _message(String message) {
    if (!mounted) return;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
  }

  // 함수이름: _locked
  // 함수역할: 조회·대화상자·공유 또는 세션 무효화로 새 명령이 제한되는지 확인한다.
  // 매개변수: 없음.
  // 반환값: 명령을 제한해야 하면 true.
  bool get _locked =>
      _control.busy ||
      _interactionActive ||
      _exporting ||
      _control.sessionInvalidated;

  // Function Name: _pickRange
  // Description: Selects a detail date inside the loaded range or a period anchor inside the retention window, rejecting stale session results.
  // Parameters: period (bool): whether selection also changes and reloads the aggregate period.
  // Returns: Future<void>; cancellation preserves selection and the interaction lock is always released.
  Future<void> _pickRange({bool period = false}) async {
    if (_locked) return;
    final control = _control;
    setState(() => _interactionActive = true);
    try {
      final today = control.today;
      final earliest = MedicationHistoryDates.earliest(today);
      final selection = await showDatePicker(
        context: context,
        locale: Locale(widget.isEnglish ? 'en' : 'ko'),
        firstDate: period ? earliest : _range.start,
        lastDate: period ? today : _range.end,
        currentDate: today,
        initialDate: _selectedDay.isBefore(earliest)
            ? earliest
            : _selectedDay.isAfter(today)
            ? today
            : _selectedDay,
        helpText: tr('복약 기록 날짜 선택', 'Select a record date'),
        confirmText: tr('조회', 'Apply'),
      );
      if (selection == null || !_isCurrent(control)) return;
      final day = MedicationHistoryDates.day(selection);
      setState(() {
        _selectedDay = day;
        if (period) {
          _anchor = day;
          _range = _periodRange(day, _period)!;
        }
      });
      if (period) await _load();
    } finally {
      _endInteraction(control);
    }
  }

  // 함수이름: _selectDay
  // 함수역할: 조회 범위 안의 날짜를 선택하고 해당 기간의 상세 목록을 펼친다.
  // 매개변수: day (DateTime): 선택 날짜.
  // 반환값: Future<void>; 잠금 또는 범위 밖이면 변경하지 않는다.
  Future<void> _selectDay(DateTime day) async {
    if (_locked) return;
    if (!_range.contains(day)) return;
    setState(() {
      _selectedDay = MedicationHistoryDates.day(day);
      _detailsExpanded[_period] = true;
    });
  }

  // Function Name: _edit
  // Description: Opens record correction only for writable current-session history, reports confirmed saves and reloads final server state after the editor closes.
  // Parameters: entry (MedicationHistoryEntry): existing report to correct.
  // Returns: Future<void>; parent-refresh failure is reported separately from a successful save.
  Future<void> _edit(MedicationHistoryEntry entry) async {
    if (_locked || _readOnly) return;
    final control = _control;
    if (control.snapshot == null || !_isCurrent(control)) return;
    setState(() => _interactionActive = true);
    try {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _MedicationHistoryEditor(
          control: control,
          entry: entry,
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
      _endInteraction(control);
    }
  }

  // 함수이름: _export
  // 함수역할: 공유 기간·민감정보 안내·목적지를 확인받아 최신 기록을 공유한다. 외부 공유창 실행을 실제 전송 완료로 주장하지 않는다.
  // 매개변수: 없음.
  // 반환값: 공유·취소·오류 안내 후 잠금을 해제하는 Future<void>.
  Future<void> _export() async {
    if (_locked) return;
    final control = _control;
    // 현재 통계를 조회한 기간을 공유 기간의 시작값으로 쓴다.
    var snapshot = control.snapshot;
    if (snapshot == null || !_isCurrent(control)) return;
    var exportRange = snapshot.range;
    var selectingDate = false;
    var preparingExport = false;
    String? exportError;
    // 외부 공유 본문은 길이 확인 때 만든 것을 그대로 보낸다.
    String? shareContent;

    // Function Name: rangeError
    // Description: Validates export date order and the retention window using the current controller clock.
    // Parameters: None.
    // Returns: Null for a valid range or a localized date-validation message.
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

    // 함수이름: chatRangeError
    // 함수역할: 공통 날짜 검증 후 채팅의 최대 조회 일수도 확인한다.
    // 매개변수: 없음.
    // 반환값: 채팅 공유 가능하면 null, 아니면 기간 제한 안내.
    String? chatRangeError() {
      final error = rangeError();
      if (error != null) return error;
      return exportRange.days > MedicationHistoryRange.maximumReadDays
          ? tr(
              '채팅 공유는 최대 31일까지예요. 다른 앱으로는 90일까지 공유할 수 있어요.',
              'Chat sharing covers up to 31 days; other apps can receive up to 90.',
            )
          : null;
    }

    // Function Name: pickExportDate
    // Description: Edits only the export-dialog range, ignoring cancelled or stale session selections and always releasing the date-selection lock.
    // Parameters: dialogContext (BuildContext): export dialog; updateDialog (StateSetter): dialog update; start (bool): start endpoint.
    // Returns: Future<void>; the underlying history range is unchanged.
    Future<void> pickExportDate(
      BuildContext dialogContext,
      StateSetter updateDialog, {
      required bool start,
    }) async {
      if (selectingDate || preparingExport || !_isCurrent(control)) return;
      updateDialog(() => selectingDate = true);
      try {
        final today = control.today;
        final earliest = MedicationHistoryDates.earliest(today);
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

    // Function Name: prepareExport
    // Description: Rechecks current access and reads fresh records before sharing, applying destination-specific date/text limits and closing only the active dialog on success.
    // Parameters: dialogContext (BuildContext): export dialog; updateDialog (StateSetter): dialog update; destination (_HistoryShareDestination): target.
    // Returns: Future<void>; failures stay in the dialog rather than claiming a completed export.
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
        final content = destination == _HistoryShareDestination.external
            ? medicationHistoryShareText(result, isEnglish: widget.isEnglish)
            : null;
        if (content != null &&
            content.length > medicationHistoryShareTextLimit) {
          updateDialog(
            () => exportError = tr(
              '공유할 기록이 많아요. 기간을 줄여 다시 시도해 주세요.',
              'Too many records to share at once. Select a shorter period.',
            ),
          );
          return;
        }
        snapshot = result;
        shareContent = content;
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
                                      '최근 90일 · 다른 앱 최대 90일 · 채팅 최대 31일',
                                      'Last 90 days · Other apps up to 90 days · Chat up to 31 days',
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
                                  // 날짜를 바꾸면 지워지는 실패 안내가 채팅 기간 안내에 가려지지 않게 한다.
                                  exportError ??
                                      rangeError() ??
                                      chatRangeError()!,
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
                            // 채팅 공유는 서버가 기간과 상태별 횟수만 만들어 보내므로 외부 공유와 구분해 알린다.
                            Text(
                              key: const Key('history-share-privacy-notice'),
                              _chatShare == null
                                  ? tr(
                                      '약 이름·복용 시각·건너뛴 이유가 포함됩니다. 공유 대상을 확인해 주세요.',
                                      'Includes medication names, taken times and skip reasons. Check who you share with.',
                                    )
                                  : tr(
                                      '다른 앱에는 약 이름·복용 시각·건너뛴 이유를, 앱 내 채팅에는 기간과 횟수만 보냅니다. 공유 대상을 확인해 주세요.',
                                      'Other apps receive medication names, taken times and skip reasons; the chat gets only the period and the counts. Check who you share with.',
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
                                      _HistoryShareDestination.external,
                                    ),
                              icon: const Icon(Icons.share_outlined),
                              label: Text(
                                tr('다른 방법으로 공유', 'Share via other apps'),
                              ),
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
            linkId: widget.chatLinkId,
          ),
        );
        if (sent != null && _isCurrent(control)) {
          if (widget.chatLinkId != null) {
            widget.onChatShared?.call();
            if (mounted) Navigator.pop(context);
            return;
          }
          _message(
            tr('$sent 님과의 채팅에 공유했어요.', 'Shared in your chat with $sent.'),
          );
        }
        return;
      }
      final content = shareContent!;
      try {
        await _exportChannel.invokeMethod<void>('shareText', {
          'content': content,
          'subject': tr('MedBuddy 복약 기록', 'MedBuddy medication history'),
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
          await _offerClipboard(content, control);
        }
      } on PlatformException catch (failure) {
        if (!_isCurrent(control)) return;
        if (const {
          'unimplemented',
          'unsupported',
          'not_implemented',
        }.contains(failure.code)) {
          await _offerClipboard(content, control);
        } else {
          _message(
            tr(
              '공유 창을 열지 못했어요. 다시 시도해 주세요.',
              'Could not open the share window. Please try again.',
            ),
          );
        }
      }
    } catch (_) {
      if (_isCurrent(control)) {
        _message(tr('내보내기를 완료하지 못했어요.', 'The export could not be completed.'));
      }
    } finally {
      _endInteraction(control);
    }
  }

  // 함수이름: _offerClipboard
  // 함수역할: 공유 미지원 시 민감정보 복사에 별도 동의를 받고 같은 세션에서만 클립보드에 쓴다.
  // 매개변수: content (String): 공유 본문; control (MedicationHistoryControl): 세션 확인 대상.
  // 반환값: 복사·취소 완료 Future<void>; 플랫폼 복사 오류는 호출자에게 전파한다.
  Future<void> _offerClipboard(
    String content,
    MedicationHistoryControl control,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          tr('이 기기에서는 공유 창을 지원하지 않아요', 'Sharing is unavailable on this device'),
        ),
        content: Text(
          tr(
            '대신 복약 기록을 클립보드에 복사할까요? 복사한 복약 정보는 다른 앱에서 읽을 수 있습니다.',
            'Copy the medication records to the clipboard instead? Other apps may be able to read copied medication information.',
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
    await Clipboard.setData(ClipboardData(text: content));
    if (_isCurrent(control)) {
      _message(tr('복약 기록을 복사했어요.', 'Medication records were copied.'));
    }
  }

  // 함수이름: build
  // 함수역할: 조회 제어기 변경을 구독하고 날짜 탐색·상태·기록 또는 공유 기간 화면을 구성한다.
  // 매개변수: context (BuildContext): 표시 위치.
  // 반환값: 스크롤 가능한 이력 화면의 AnimatedBuilder.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _control,
    builder: (context, _) {
      final snapshot = _control.snapshot;
      final scrollHeader =
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
        onBackRequested: widget.showBackButton
            ? () => Navigator.maybePop(context)
            : null,
        actions: [
          IconButton(
            tooltip: tr('새로고침', 'Refresh'),
            onPressed: _locked ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: tr('공유', 'Share'),
            onPressed: _locked || snapshot == null ? null : _export,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
        bottom: widget.sharedRange != null && snapshot != null
            ? _progress(snapshot)
            : null,
      );
      return ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          backgroundColor: MedBuddyColors.pageBackground,
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                if (!scrollHeader) header,
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: ListView(
                        key: const Key('history-scroll'),
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (scrollHeader) header,
                          if (widget.sharedRange != null)
                            ..._sharedPeriodBody(snapshot)
                          else
                            ..._dashboard(snapshot),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  // Function Name: _dashboard
  // Description: Builds period tabs, collapsible charts and selected-day details from the current lookup snapshot.
  // Parameters: snapshot (MedicationHistorySnapshot?): loaded period or null while unavailable.
  // Returns: Ordered dashboard widgets, preserving each period tab expansion state.
  List<Widget> _dashboard(MedicationHistorySnapshot? snapshot) {
    final chartOpen = _chartExpanded[_period] ?? true;
    final detailsOpen = _detailsExpanded[_period] ?? true;
    return [
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: MedBuddyColors.primary.withValues(alpha: 0.06),
          borderRadius: MedBuddyRadii.small,
        ),
        child: Row(
          children: [
            for (final period in _HistoryPeriod.values)
              Expanded(
                child: Semantics(
                  selected: _period == period,
                  child: TextButton(
                    key: ValueKey('history-tab-${period.name}'),
                    onPressed: _locked ? null : () => _changePeriod(period),
                    style: TextButton.styleFrom(
                      backgroundColor: _period == period
                          ? MedBuddyColors.surface
                          : Colors.transparent,
                      foregroundColor: _period == period
                          ? MedBuddyColors.primary
                          : MedBuddyColors.textMuted,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: MedBuddyRadii.small,
                      ),
                    ),
                    child: Text(switch (period) {
                      _HistoryPeriod.week => tr('주간', 'Weekly'),
                      _HistoryPeriod.month => tr('월간', 'Monthly'),
                      _HistoryPeriod.custom => tr('기간 선택', 'Date range'),
                    }, textAlign: TextAlign.center),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (_period == _HistoryPeriod.custom)
        _customRangeControls()
      else
        _periodNavigation(),
      const SizedBox(height: 12),
      // 수정 저장 뒤 다시 읽기 전까지는 자료도 오류도 없으므로 빈 화면 대신 진행을 표시한다.
      if (_control.loading || (snapshot == null && _control.error == null))
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_control.error != null) ...[
        Text(
          _failureText(_control.error!, widget.isEnglish),
          key: const Key('history-load-error'),
          style: const TextStyle(color: MedBuddyColors.danger),
        ),
        if (!_control.sessionInvalidated) const SizedBox(height: 12),
        if (!_control.sessionInvalidated)
          OutlinedButton.icon(
            onPressed: _locked ? null : _reload,
            icon: const Icon(Icons.refresh),
            label: Text(tr('다시 시도', 'Retry')),
          ),
      ] else if (snapshot != null) ...[
        _sectionFrame(
          key: 'history-section-summary',
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MedicationHistoryChartsSummary(
              snapshot: snapshot,
              isEnglish: widget.isEnglish,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_period != _HistoryPeriod.custom) ...[
          _sectionFrame(
            key: 'history-section-dates',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionHeading(
                    key: 'history-toggle-chart',
                    title: tr('날짜별 기록', 'Records by date'),
                    open: chartOpen,
                    onPressed: () =>
                        setState(() => _chartExpanded[_period] = !chartOpen),
                    trailing: _period == _HistoryPeriod.week
                        ? tr('단위: 회', 'Doses')
                        : null,
                  ),
                  if (chartOpen && _period == _HistoryPeriod.week)
                    MedicationHistoryWeekChart(
                      snapshot: snapshot,
                      weekStart: _anchor.subtract(
                        Duration(days: _anchor.weekday - 1),
                      ),
                      today: _control.today,
                      selected: _selectedDay,
                      isEnglish: widget.isEnglish,
                      enabled: !_locked,
                      onDaySelected: _selectDay,
                    ),
                  if (chartOpen && _period == _HistoryPeriod.month)
                    MedicationHistoryMonthCalendar(
                      month: DateTime.utc(_anchor.year, _anchor.month),
                      today: _control.today,
                      selected: _selectedDay,
                      summaries: MedicationHistoryDaySummary.fromSnapshot(
                        snapshot,
                      ),
                      isEnglish: widget.isEnglish,
                      enabled: !_locked,
                      onDaySelected: _selectDay,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _sectionFrame(
          key: 'history-section-details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _sectionHeading(
                  key: 'history-toggle-details',
                  title: tr('일별 상세 기록', 'Daily details'),
                  open: detailsOpen,
                  onPressed: () =>
                      setState(() => _detailsExpanded[_period] = !detailsOpen),
                ),
              ),
              if (detailsOpen) ...[
                _dayNavigation(),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _dailySummary(snapshot),
                ),
                const SizedBox(height: 8),
                if (!snapshot.items.any(
                  (entry) => entry.scheduleDate == _selectedDay,
                ))
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr(
                        '이 날짜에는 복약 일정이나 기록이 없어요.',
                        'No scheduled doses or records on this date.',
                      ),
                      style: MedBuddyTextStyles.menuBody,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: _slotCards(
                      snapshot.items.where(
                        (entry) => entry.scheduleDate == _selectedDay,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  // 함수이름: _sectionFrame
  // 함수역할: 그림자 없는 테두리 안에 이력 구역을 배치하고 넘치는 내용을 자른다.
  // 매개변수: key (String): 구역 식별자; child (Widget): 내용.
  // 반환값: 구역 Container.
  Widget _sectionFrame({required String key, required Widget child}) =>
      Container(
        key: ValueKey(key),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: MedBuddyColors.surface,
          border: Border.all(color: MedBuddyColors.cardBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      );

  // 함수이름: _sectionHeading
  // 함수역할: 구역 전체 제목을 접기·펼치기 명령으로 만들고 잠금 중에는 조작을 막는다.
  // 매개변수: key/title (String): 식별자·제목; open (bool): 펼침 여부; onPressed (VoidCallback): 변경; trailing (String?): 보조 문구.
  // 반환값: 펼침 상태를 접근성으로 제공하는 제목 행.
  Widget _sectionHeading({
    required String key,
    required String title,
    required bool open,
    required VoidCallback onPressed,
    String? trailing,
  }) => Semantics(
    expanded: open,
    child: InkWell(
      key: ValueKey(key),
      onTap: _locked ? null : onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (trailing != null)
              Text(
                trailing,
                style: const TextStyle(
                  fontSize: 13,
                  color: MedBuddyColors.textMuted,
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              open ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              color: MedBuddyColors.primary,
            ),
          ],
        ),
      ),
    ),
  );

  // 함수이름: _periodNavigation
  // 함수역할: 현재 주·월의 표시 범위와 이동 가능 기간을 계산해 탐색 버튼을 배치한다.
  // 매개변수: 없음.
  // 반환값: 이전·다음 기간 탐색 위젯.
  Widget _periodNavigation() {
    final isMonth = _period == _HistoryPeriod.month;
    final previous = isMonth
        ? DateTime.utc(_anchor.year, _anchor.month - 1)
        : _anchor.subtract(const Duration(days: 7));
    final next = isMonth
        ? DateTime.utc(_anchor.year, _anchor.month + 1)
        : _anchor.add(const Duration(days: 7));
    final monday = _anchor.subtract(Duration(days: _anchor.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final title = isMonth
        ? tr(
            '${_anchor.year}년 ${_anchor.month}월',
            '${_anchor.year}.${_anchor.month.toString().padLeft(2, '0')}',
          )
        : '${MedicationHistoryDates.format(monday)} ~ ${MedicationHistoryDates.format(sunday)}';
    return Row(
      children: [
        IconButton(
          key: ValueKey(
            isMonth ? 'history-previous-month' : 'history-previous-week',
          ),
          tooltip: tr('이전 기간', 'Previous period'),
          onPressed: _locked || _periodRange(previous, _period) == null
              ? null
              : () => _changePeriod(_period, anchor: previous),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: TextButton(
            key: const Key('history-select-period'),
            onPressed: _locked ? null : () => _pickRange(period: true),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        IconButton(
          key: ValueKey(isMonth ? 'history-next-month' : 'history-next-week'),
          tooltip: tr('다음 기간', 'Next period'),
          onPressed: _locked || _periodRange(next, _period) == null
              ? null
              : () => _changePeriod(_period, anchor: next),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  // 함수이름: _dayNavigation
  // 함수역할: 선택 날짜를 표시하고 조회 범위 안에서 전날·다음 날 상세로 이동하게 한다.
  // 매개변수: 없음.
  // 반환값: 상세 날짜 탐색 행.
  Widget _dayNavigation() => Row(
    key: const Key('history-date-navigation'),
    children: [
      IconButton(
        key: const Key('history-previous-day'),
        tooltip: tr('이전 날짜', 'Previous day'),
        onPressed: _locked || !_selectedDay.isAfter(_range.start)
            ? null
            : () => _selectDay(_selectedDay.subtract(const Duration(days: 1))),
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: TextButton(
          key: const Key('history-select-date'),
          onPressed: _locked ? null : _pickRange,
          child: Text(
            MedicationHistoryDates.format(_selectedDay),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      IconButton(
        key: const Key('history-next-day'),
        tooltip: tr('다음 날짜', 'Next day'),
        onPressed: _locked || !_selectedDay.isBefore(_range.end)
            ? null
            : () => _selectDay(_selectedDay.add(const Duration(days: 1))),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  // 함수이름: _customRangeControls
  // 함수역할: 직접 지정 기간의 시작일·종료일 선택과 기간 안내를 표시한다.
  // 매개변수: 없음.
  // 반환값: 잠금 상태를 반영한 사용자 기간 입력 구역.
  Widget _customRangeControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final start in [true, false]) ...[
            if (!start) const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      start ? '시작일' : '종료일',
                      start ? 'Start date' : 'End date',
                    ),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton(
                    key: ValueKey(
                      start ? 'history-range-start' : 'history-range-end',
                    ),
                    onPressed: _locked ? null : () => _pickCustomDate(start),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      MedicationHistoryDates.format(
                        start ? _customStart : _customEnd,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ],
  );

  // Function Name: _pickCustomDate
  // Description: Picks a custom range endpoint within retained days and reloads once only for a changed, valid selection in the same session.
  // Parameters: start (bool): start endpoint rather than end endpoint.
  // Returns: Future<void>; cancellation and stale results are ignored, then interaction state is released.
  Future<void> _pickCustomDate(bool start) async {
    if (_locked) return;
    final control = _control;
    setState(() => _interactionActive = true);
    try {
      final earliest = MedicationHistoryDates.earliest(control.today);
      final first = start
          ? earliest
          : (_customStart.isBefore(earliest) ? earliest : _customStart);
      final last = start
          ? (_customEnd.isBefore(earliest) ? earliest : _customEnd)
          : control.today;
      final initial = start ? _customStart : _customEnd;
      final selected = await showDatePicker(
        context: context,
        locale: Locale(widget.isEnglish ? 'en' : 'ko'),
        firstDate: first,
        lastDate: last,
        currentDate: control.today,
        initialDate: initial.isBefore(first)
            ? first
            : initial.isAfter(last)
            ? last
            : initial,
        helpText: tr(
          start ? '시작일 선택' : '종료일 선택',
          start ? 'Select start date' : 'Select end date',
        ),
      );
      if (selected == null || !_isCurrent(control)) return;
      final day = MedicationHistoryDates.day(selected);
      if (day == initial || day.isBefore(first) || day.isAfter(last)) return;
      setState(() {
        if (start) {
          _customStart = day;
        } else {
          _customEnd = day;
        }
        _range = _periodRange(_anchor, _HistoryPeriod.custom)!;
        _customStart = _range.start;
        _customEnd = _range.end;
        if (!_range.contains(_selectedDay)) _selectedDay = _range.end;
      });
      await _load();
    } finally {
      _endInteraction(control);
    }
  }

  // 함수이름: _dailySummary
  // 함수역할: 선택한 하루의 복용·미복용·미기록 수를 세어 기간 전체 통계와 분리해 표시한다.
  // 매개변수: snapshot (MedicationHistorySnapshot): 조회한 기간 자료.
  // 반환값: 하루 요약 위젯.
  Widget _dailySummary(MedicationHistorySnapshot snapshot) {
    final entries = snapshot.items.where(
      (item) => item.scheduleDate == _selectedDay,
    );
    final counts = MedicationHistoryChartCounts.fromEntries(entries);
    final values = [counts.taken, counts.skipped, counts.unrecorded];
    return Wrap(
      key: const Key('history-status-summary'),
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final status in MedicationHistoryStatus.values)
          Text(
            '${status.label(widget.isEnglish)} ${values[status.index]}',
            style: MedBuddyTextStyles.menuBody.copyWith(
              color: _statusColor(status),
              fontWeight: FontWeight.w700,
            ),
          ),
        if (entries.any((entry) => entry.isAsNeeded))
          Text(
            '${tr('필요시 복용', 'As needed')} ${counts.asNeeded}',
            style: MedBuddyTextStyles.menuBody.copyWith(
              color: MedBuddyColors.infoBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  // 함수이름: _sharedPeriodBody
  // 함수역할: 채팅에서 공유된 기간의 조회 결과를 읽기 전용 요약과 날짜별 기록으로 표시한다.
  // 매개변수: snapshot (MedicationHistorySnapshot?): 공유 기간 조회 자료.
  // 반환값: 공유 기간 본문 위젯 목록.
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
        if (!_control.sessionInvalidated) const SizedBox(height: 12),
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
                      style: MedBuddyTextStyles.menuBody.copyWith(
                        color: _statusColor(status),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
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
              style: MedBuddyTextStyles.menuBody,
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
          ..._slotCards(
            snapshot.items.where((entry) => entry.scheduleDate == day),
          ),
        ],
      ],
    ];
  }

  // Function Name: _progress
  // Description: Displays period completion totals separately from as-needed reports.
  // Parameters: snapshot (MedicationHistorySnapshot): aggregate records.
  // Returns: Progress summary without treating as-needed reports as scheduled-dose denominator.
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

  // 함수이름: _slotCards
  // 함수역할: 기록이 있는 시간대를 순서대로 묶어 각 시간대 카드로 변환한다.
  // 매개변수: entries (Iterable<MedicationHistoryEntry>): 표시 대상 기록.
  // 반환값: 시간대별 위젯 목록.
  List<Widget> _slotCards(Iterable<MedicationHistoryEntry> entries) {
    final cards = <Widget>[];
    for (final slot in [...medicationScheduleSlotKeys, 'as_needed']) {
      final slotEntries = entries
          .where(
            (entry) =>
                slot == 'as_needed' ? entry.isAsNeeded : entry.slotKey == slot,
          )
          .toList();
      if (slotEntries.isNotEmpty) {
        cards.add(_slotCard(slot, slotEntries));
      }
    }
    return cards;
  }

  // 함수이름: _slotCard
  // 함수역할: 시간대 제목과 해당 기록 행을 묶어 표시한다.
  // 매개변수: slot (String): 시간대 키; entries (List<MedicationHistoryEntry>): 해당 시간대 기록.
  // 반환값: 시간대 카드.
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

  // Function Name: _entryTile
  // Description: Displays one self-reported record with status/time/reason and enables correction only when writable and unlocked.
  // Parameters: entry (MedicationHistoryEntry): report to display.
  // Returns: Record tile with wrapping text for larger fonts.
  Widget _entryTile(MedicationHistoryEntry entry) => Container(
    key: ValueKey('history-entry-${entry.key}'),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KeepWordsText(
                    entry.itemName,
                    style: MedBuddyTextStyles.menuTitle.copyWith(
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
                    style: MedBuddyTextStyles.menuBody.copyWith(
                      color: _statusColor(entry.status),
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
            style: MedBuddyTextStyles.menuBody,
          ),
        if (entry.recordedAt != null)
          Text(
            '${tr('기록 시각', 'Recorded at')}: ${MedicationHistoryDates.timestamp(entry.recordedAt)}',
            style: MedBuddyTextStyles.menuBody,
          ),
        if (entry.reason.isNotEmpty)
          Text(
            '${tr('이유', 'Reason')}: ${entry.reason}',
            style: MedBuddyTextStyles.menuBody,
          ),
      ],
    ),
  );
}

// 클래스명: _HistoryChatShareDialog
// 역할: 기간과 수신자를 확인한 뒤 연동 채팅으로 기록을 공유한다.
// 주요 책임: 현재 채팅에서 진입하면 해당 연동만 선택하고 전송 실패를 재시도한다.
// 속성: history (MedicationHistoryControl): 세션; share (ShareMedicationHistory): 전송; range (MedicationHistoryRange): 기간; isEnglish (bool): 언어; linkId (int?): 고정 대상.
class _HistoryChatShareDialog extends StatefulWidget {
  // 함수이름: _HistoryChatShareDialog
  // 함수역할: 조회 세션·공유 명령·기간과 선택적 고정 수신자를 연결한다.
  // 매개변수: history (MedicationHistoryControl): 조회기; share (ShareMedicationHistory): 공유기; range (MedicationHistoryRange): 기간; isEnglish (bool): 언어; linkId (int?): 고정 연동.
  // 반환값: 새 _HistoryChatShareDialog.
  const _HistoryChatShareDialog({
    required this.history,
    required this.share,
    required this.range,
    required this.isEnglish,
    this.linkId,
  });
  final MedicationHistoryControl history;
  final ShareMedicationHistory share;
  final MedicationHistoryRange range;
  final bool isEnglish;
  final int? linkId;

  // 함수이름: createState
  // 함수역할: 수신자 조회와 전송의 진행·실패 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _HistoryChatShareDialogState.
  @override
  State<_HistoryChatShareDialog> createState() =>
      _HistoryChatShareDialogState();
}

// 클래스명: _HistoryChatShareDialogState
// 역할: 공유 가능한 수신자 선택과 전송 상태를 관리한다.
// 주요 책임: 조회·전송 실패를 분리하고 성공 시 상대 이름으로 대화상자를 닫는다.
// 속성: _recipients (List<PatientCaregiverLink>): 수신자; _selected (int?): 선택 ID; _loading/_sending/_loadFailed/_sendFailed (bool): 작업 상태.
class _HistoryChatShareDialogState extends State<_HistoryChatShareDialog> {
  List<PatientCaregiverLink> _recipients = const [];
  int? _selected;
  bool _loading = true;
  bool _sending = false;
  bool _loadFailed = false;
  bool _sendFailed = false;
  // 함수이름: tr
  // 함수역할: 공유 확인창의 언어에 맞는 문구를 선택한다.
  // 매개변수: ko/en (String): 한국어·영어 문구.
  // 반환값: 선택한 문구.
  String tr(String ko, String en) => widget.isEnglish ? en : ko;

  // 함수이름: initState
  // 함수역할: 공유 수신자를 비동기로 조회한다.
  // 매개변수: 없음.
  // 반환값: 없음.
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  // 함수이름: _load
  // 함수역할: 수신자를 다시 읽고 지정 연동이 있으면 그 대상만 남겨 자동 선택한다.
  // 매개변수: 없음.
  // 반환값: 조회 완료 Future<void>; 오류는 재시도 상태로 표시하고 종료된 화면은 갱신하지 않는다.
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
      setState(() {
        _recipients = widget.linkId == null
            ? links
            : links.where((link) => link.linkId == widget.linkId).toList();
        if (widget.linkId != null && _recipients.length == 1) {
          _selected = widget.linkId;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 함수이름: _send
  // 함수역할: 선택한 연동에 확정 기간을 전송하고 성공 시 상대 이름을 반환하며 창을 닫는다.
  // 매개변수: 없음.
  // 반환값: Future<void>; 선택 없음·작업 중은 무시하고 전송 오류는 창에 남긴다.
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

  // 함수이름: build
  // 함수역할: 유효한 세션에는 수신자·기간·전송 상태를, 무효화된 세션에는 종료 안내를 표시한다.
  // 매개변수: context (BuildContext): 대화상자 위치.
  // 반환값: 세션 변경을 구독하는 AnimatedBuilder.
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

// Class Name: _MedicationHistoryEditor
// Role: A dialog correcting one existing self-reported medication event.
// Responsibilities: Passes the original event and the same patient controller to state that validates and confirms corrections.
// Attributes: control (MedicationHistoryControl): patient/session owner; entry (MedicationHistoryEntry): original event; isEnglish (bool): language.
class _MedicationHistoryEditor extends StatefulWidget {
  // 함수이름: _MedicationHistoryEditor
  // 함수역할: 동일 환자의 조회 제어기와 정정할 보고를 연결한다.
  // 매개변수: control (MedicationHistoryControl): 조회기; entry (MedicationHistoryEntry): 원본; isEnglish (bool): 언어.
  // 반환값: 새 _MedicationHistoryEditor.
  const _MedicationHistoryEditor({
    required this.control,
    required this.entry,
    required this.isEnglish,
  });
  final MedicationHistoryControl control;
  final MedicationHistoryEntry entry;
  final bool isEnglish;

  // 함수이름: createState
  // 함수역할: 정정 입력과 응답 미확인 요청을 보존할 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 _MedicationHistoryEditorState.
  @override
  State<_MedicationHistoryEditor> createState() =>
      _MedicationHistoryEditorState();
}

// Class Name: _MedicationHistoryEditorState
// Role: Validates corrections and preserves uncertain writes under the same operation ID.
// Responsibilities: Distinguishes validation rejection from version conflict and prevents editing an unresolved write.
// Attributes: _status (MedicationHistoryStatus): report; _actualDate/_actualTime: Korea wall time; _reason (TextEditingController): reason; _pending (MedicationHistoryChange?): fixed retry; _error (Object?): failure; _submitting/_conflict (bool): locks.
class _MedicationHistoryEditorState extends State<_MedicationHistoryEditor> {
  late MedicationHistoryStatus _status;
  late DateTime _actualDate;
  late TimeOfDay _actualTime;
  late final TextEditingController _reason;
  MedicationHistoryChange? _pending;
  Object? _error;
  bool _submitting = false;
  bool _conflict = false;

  // 함수이름: tr
  // 함수역할: 편집기의 언어에 맞는 문구를 선택한다.
  // 매개변수: ko/en (String): 한국어·영어 문구.
  // 반환값: 선택한 문구.
  String tr(String ko, String en) => widget.isEnglish ? en : ko;
  // 함수이름: _locked
  // 함수역할: 정정 확인·전송 중이거나 세션이 무효화되었는지 확인한다.
  // 매개변수: 없음.
  // 반환값: 저장 동작을 막아야 하면 true.
  bool get _locked => _submitting || widget.control.sessionInvalidated;
  // 함수이름: _fieldsLocked
  // 함수역할: 응답 미확인 요청이나 버전 충돌을 포함해 입력 변경 금지 상태를 판단한다.
  // 매개변수: 없음.
  // 반환값: 입력 필드를 잠가야 하면 true.
  bool get _fieldsLocked => _locked || _pending != null || _conflict;
  // 함수이름: _clearEditableValidationError
  // 함수역할: 입력 가능한 상태에서 형식·422 검증 오류만 지우고 미확인 전송·충돌 오류는 보존한다.
  // 매개변수: 없음.
  // 반환값: 없음.
  void _clearEditableValidationError() {
    final error = _error;
    if (!_fieldsLocked &&
        (error is FormatException ||
            (error is ApiRequestException && error.statusCode == 422))) {
      _error = null;
    }
  }

  // Function Name: initState
  // Description: Seeds fields from the report, converting actual timestamps to Korean wall time and retaining its original reason.
  // Parameters: None.
  // Returns: No return value; absent timestamps use the scheduled day and current Korean time.
  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _status = entry.status;
    final now = MedicationHistoryDates.wallTime(widget.control.now);
    final actualTakenAt = entry.actualTakenAt;
    final time = actualTakenAt == null
        ? null
        : MedicationHistoryDates.wallTime(actualTakenAt);
    _actualDate = time == null
        ? entry.scheduleDate
        : MedicationHistoryDates.day(time);
    _actualTime = TimeOfDay(
      hour: time?.hour ?? now.hour,
      minute: time?.minute ?? now.minute,
    );
    _reason = TextEditingController(text: entry.reason);
  }

  // 함수이름: dispose
  // 함수역할: 사유 입력 제어기를 해제한다.
  // 매개변수: 없음.
  // 반환값: 없음.
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  // Function Name: _pickActualDate
  // Description: Picks an actual-taken date within retention and clears only editable validation errors after a changed valid selection.
  // Parameters: None.
  // Returns: Future<void>; cancellation, disposal or a locked editor keeps the original date.
  Future<void> _pickActualDate() async {
    if (_fieldsLocked) return;
    final selected = await showDatePicker(
      context: context,
      locale: Locale(widget.isEnglish ? 'en' : 'ko'),
      initialDate: _actualDate,
      firstDate: MedicationHistoryDates.earliest(widget.control.today),
      lastDate: widget.control.today,
      currentDate: widget.control.today,
      helpText: tr('실제 복용 날짜', 'Actual taken date'),
    );
    if (!mounted || selected == null || _fieldsLocked) return;
    final selectedDay = MedicationHistoryDates.day(selected);
    if (selectedDay == _actualDate) return;
    setState(() {
      _actualDate = selectedDay;
      _clearEditableValidationError();
    });
  }

  // 함수이름: _pickTime
  // 함수역할: 실제 복용 시·분을 한국 시간으로 선택하고 입력 가능한 변경만 반영한다.
  // 매개변수: 없음.
  // 반환값: 선택 완료 Future<void>; 미래 시각 검증은 저장 시 수행한다.
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

  // Function Name: _buildChange
  // Description: Freezes the entered report under a new operation ID, preserving the original event and converting Korean taken time to an instant.
  // Parameters: None.
  // Returns: MedicationHistoryChange; taken time is omitted unless taken, and reason is retained only when skipped.
  MedicationHistoryChange _buildChange() => MedicationHistoryChange(
    entry: widget.entry,
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

  // Function Name: _save
  // Description: Validates and confirms a correction, then retries uncertain writes with the same operation ID. A 409 blocks edits; a 422 releases the payload for correction.
  // Parameters: None.
  // Returns: Future<void>; confirmed persistence closes with true, failures remain visible and the submission lock is always released.
  Future<void> _save() async {
    if (_locked || _conflict) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      widget.control.ensureSession();
      final change = _pending ?? _buildChange();
      change.validate(widget.control.now);
      if (_pending == null) {
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
      await widget.control.save(change);
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
        }
        // 명시적인 입력 거절만 수정 가능하게 풀고 응답 유실은 같은 작업 ID로 재시도한다.
        if (failure is ApiRequestException && failure.statusCode == 422) {
          _pending = null;
        }
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Function Name: build
  // Description: Shows editable status/time/reason fields or hides them behind a session-ended notice when authorization changes.
  // Parameters: context (BuildContext): Dialog location.
  // Returns: AnimatedBuilder respecting pending-write and conflict locks.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.control,
    builder: (context, _) => widget.control.sessionInvalidated
        ? _sessionEndedDialog(context, widget.isEnglish)
        : PopScope(
            canPop: !_submitting,
            child: AlertDialog(
              title: Text(tr('복약 기록 수정', 'Edit medication record')),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.entry.itemName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${widget.entry.isAsNeeded ? tr('기록일', 'Record date') : tr('예정일', 'Scheduled date')} ${MedicationHistoryDates.format(widget.entry.scheduleDate)} · ${widget.entry.slotLabel(widget.isEnglish)}',
                      ),
                      const SizedBox(height: 12),
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
                            for (final status in MedicationHistoryStatus.values)
                              if (!widget.entry.isAsNeeded ||
                                  status != MedicationHistoryStatus.skipped ||
                                  widget.entry.status ==
                                      MedicationHistoryStatus.skipped)
                                RadioListTile<MedicationHistoryStatus>(
                                  value: status,
                                  enabled: !_fieldsLocked,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    widget.entry.isAsNeeded &&
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
                              onPressed: _fieldsLocked ? null : _pickActualDate,
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
                          widget.entry.isAsNeeded
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
                      if (widget.entry.recordedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '${tr('이전 기록 시각', 'Previously recorded at')}: '
                            '${MedicationHistoryDates.timestamp(widget.entry.recordedAt)}',
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
                    onPressed: _locked ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      _pending != null
                          ? tr('같은 기록 재시도', 'Retry record')
                          : tr('기록 저장', 'Save record'),
                    ),
                  ),
              ],
            ),
          ),
  );
}

// 함수이름: _sessionEndedDialog
// 함수역할: 세션 변경으로 기록 내용을 더 표시할 수 없음을 알리고 닫기를 제공한다.
// 매개변수: context (BuildContext): 현재 대화상자; english (bool): 영어 여부.
// 반환값: 세션 종료 AlertDialog.
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

// 함수이름: _statusColor
// 함수역할: 복용·미복용·미기록에 대응하는 의미 색상을 선택한다.
// 매개변수: status (MedicationHistoryStatus): 보고 상태.
// 반환값: 앱 테마 Color.
Color _statusColor(MedicationHistoryStatus status) => switch (status) {
  MedicationHistoryStatus.taken => MedBuddyColors.primary,
  MedicationHistoryStatus.skipped => MedBuddyColors.reminderAccent,
  MedicationHistoryStatus.unrecorded => MedBuddyColors.textMuted,
};

// 함수이름: _failureText
// 함수역할: 내부 응답을 그대로 노출하지 않고 세션·입력·권한·충돌·연결 실패를 구분해 안내한다.
// 매개변수: failure (Object): 발생 오류; english (bool): 영어 여부.
// 반환값: 안전한 사용자용 오류 문구.
String _failureText(Object failure, bool english) {
  // 함수이름: tr
  // 함수역할: 오류 설명의 요청 언어를 선택한다.
  // 매개변수: ko/en (String): 한국어·영어 문구.
  // 반환값: english에 해당하는 문구.
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
