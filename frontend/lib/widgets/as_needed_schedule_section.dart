// 파일명: as_needed_schedule_section.dart
// 역할: 필요시 약의 오늘 복용 보고·미확인 요청 복원·일회 확인 알림을 표시한다.
// 필요시 약의 새 복용은 일정에서 기록하고 기존 보고의 정정은 복약 기록에 맡긴다.
import 'dart:async';
import 'package:flutter/material.dart';
import '../boundaries/medication_image_viewer_boundary.dart';
import '../controls/as_needed_check_reminder_control.dart';
import '../controls/medication_history_control.dart';
import '../entities/medication_history_entity.dart';
import '../entities/medication_schedule_entity.dart';
import '../services/manual_medication_image_store.dart';
import '../services/api_response_parser.dart';
import '../theme/medbuddy_theme.dart';
import 'medication_schedule_header.dart';
import 'medication_thumbnail.dart';

// 클래스명: AsNeededScheduleSection
// 역할: 필요시 약의 오늘 복용 기록과 선택적 확인 알림을 표시한다.
// 주요 책임: 본인 기록·재시도와 보호자 읽기 전용 표시를 구분하고 날짜·활성 상태 변경에 맞춰 조회한다.
// 속성: patientHash/control: 환자 기록 범위; reminderControl/imageStore: 알림·기기 사진; 읽기 전용·활성·갱신·표시 설정.
class AsNeededScheduleSection extends StatefulWidget {
  // 함수이름: AsNeededScheduleSection
  // 함수역할: 필요시 복용 영역의 계정·조회·알림 및 표시 조건을 구성한다.
  // 매개변수: key: 식별자; patientHash/isEnglish: 계정·언어; control/imageStore/reminderControl: 선택적 경계; refreshInProgress/refreshVersion/isActive: 갱신 조건; emptyState: 빈 화면; notificationsAllowed/readOnly: 권한; readOnlyHeaderAction/readOnlyStatusLabel: 보호자 표시.
  // 반환값: 필요시 일정 위젯; 주입 제어기의 수명은 호출자가 관리한다.
  const AsNeededScheduleSection({
    super.key,
    required this.patientHash,
    required this.isEnglish,
    this.refreshInProgress = false,
    this.emptyState = const SizedBox.shrink(),
    this.control,
    this.imageStore = const ManualMedicationImageStore(),
    this.reminderControl,
    this.notificationsAllowed = true,
    this.readOnly = false,
    this.isActive = true,
    this.refreshVersion = 0,
    this.readOnlyHeaderAction,
    this.readOnlyStatusLabel,
  });
  final String patientHash;
  final bool isEnglish;
  final bool refreshInProgress;
  final Widget emptyState;
  final MedicationHistoryControl? control;
  final ManualMedicationImageStore imageStore;
  final AsNeededCheckReminderControl? reminderControl;
  final bool notificationsAllowed;
  final bool readOnly;
  final bool isActive;
  final int refreshVersion;
  // 보호자 알림은 환자의 확인 알림과 분리해 부모 화면에서 관리한다.
  final Widget? readOnlyHeaderAction;
  final String? readOnlyStatusLabel;
  // 함수이름: createState
  // 함수역할: 조회와 기록 및 자정 갱신을 관리할 상태를 만든다.
  // 매개변수: 없음.
  // 반환값: 새 필요시 일정 State.
  @override
  State<AsNeededScheduleSection> createState() =>
      _AsNeededScheduleSectionState();
}

// Class Name: _AsNeededScheduleSectionState
// Role: Manages current-day as-needed history, pending saves and optional device reminders.
// Responsibilities: Recover pending intentions, prevent overlapping records and refresh after lifecycle/date changes while preserving read-only caregiver behavior.
// Attributes: Controllers own history/reminders; timers and flags coordinate reloads; photos/snapshot/error fields retain display state.
class _AsNeededScheduleSectionState extends State<AsNeededScheduleSection>
    with WidgetsBindingObserver {
  late final MedicationHistoryControl _control;
  late final AsNeededCheckReminderControl _reminder;
  Timer? _dayTimer;
  bool _recording = false;
  bool _reminderOpen = false;
  bool _reloadRequested = false;
  MedicationHistorySnapshot? _lastSnapshot;
  // 기기의 미확인 기록 저장소를 열지 못하면 목록과 횟수는 서버 기준으로 보여 주되, 보내지 못한
  // 기록과 겹칠 수 있는 새 기록은 막는다.
  bool _pendingStoreUnavailable = false;
  final Map<int, String> _photos = {};
  String? _saveError;
  // 함수이름: tr
  // 함수역할: 필요시 복용 화면의 안내 문구를 언어에 맞게 고른다.
  // 매개변수: ko/en: 한국어와 영어 문구.
  // 반환값: 현재 위젯 언어의 문구.
  String tr(String ko, String en) => widget.isEnglish ? en : ko;
  // 함수이름: _readOnly
  // 함수역할: 화면 또는 기록 제어기가 요청한 읽기 전용 제한을 함께 적용한다.
  // 매개변수: 없음.
  // 반환값: 둘 중 하나라도 읽기 전용이면 true.
  bool get _readOnly => widget.readOnly || _control.readOnly;
  // 함수이름: _locked
  // 함수역할: 진행 중 기록·조회 또는 무효화된 세션 때문에 입력을 잠가야 하는지 확인한다.
  // 매개변수: 없음.
  // 반환값: 입력을 잠글 상태이면 true.
  bool get _locked =>
      _recording || _control.busy || _control.sessionInvalidated;

  // 함수이름: initState
  // 함수역할: 기록·알림 경계를 준비하고 생명주기·자정 갱신과 최초 조회를 시작한다.
  // 매개변수: 없음.
  // 반환값: 없음; 최초 조회와 알림 복원은 비동기로 시작한다.
  @override
  void initState() {
    super.initState();
    _control =
        widget.control ??
        MedicationHistoryControl(
          patientHash: widget.patientHash,
          readOnly: widget.readOnly,
        );
    _reminder =
        widget.reminderControl ??
        AsNeededCheckReminderControl(
          patientHash: widget.patientHash,
          ensureSession: _control.ensureSession,
          now: () => _control.now,
        );
    WidgetsBinding.instance.addObserver(this);
    _scheduleDayRefresh();
    unawaited(_load());
    unawaited(_restoreReminder());
  }

  // 함수이름: _restoreReminder
  // 함수역할: 활성 본인 화면에서만 저장된 확인 알림을 현재 허용·언어 설정으로 복원한다.
  // 매개변수: 없음.
  // 반환값: 복원 시도 완료; 알림 오류는 삼켜 복용 기록 이용을 막지 않는다.
  Future<void> _restoreReminder() async {
    // 보호자 조회는 환자의 기기 알림이나 로컬 설정을 만들거나 변경하지 않는다.
    if (_readOnly || !widget.isActive) return;
    try {
      await _reminder.restore(
        allowed: widget.notificationsAllowed,
        isEnglish: widget.isEnglish,
      );
    } catch (_) {
      /* 알림 권한·기기 기능을 읽지 못해도 복용 기록은 계속 이용할 수 있다. */
    }
    if (mounted) setState(() {});
  }

  // 함수이름: didUpdateWidget
  // 함수역할: 부모 갱신 완료·버전 변경·재활성화에 기록을 다시 읽고 알림 허용 변경을 반영한다.
  // 매개변수: oldWidget: 이전 위젯 구성.
  // 반환값: 없음; 필요한 작업만 비동기로 시작한다.
  @override
  void didUpdateWidget(covariant AsNeededScheduleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.refreshInProgress && !widget.refreshInProgress) ||
        oldWidget.refreshVersion != widget.refreshVersion ||
        (!oldWidget.isActive && widget.isActive)) {
      unawaited(_load());
    }
    if (oldWidget.notificationsAllowed != widget.notificationsAllowed) {
      unawaited(_restoreReminder());
    }
  }

  // 함수이름: didChangeAppLifecycleState
  // 함수역할: 앱 복귀 시 날짜 타이머를 다시 맞추고 기록과 알림을 복원한다.
  // 매개변수: state: 새 앱 생명주기 상태.
  // 반환값: 없음; resumed 이외 상태는 처리하지 않는다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleDayRefresh();
      unawaited(_load());
      unawaited(_restoreReminder());
    }
  }

  // 함수이름: _scheduleDayRefresh
  // 함수역할: 기준 시간대의 다음 자정 1초 뒤에 날짜별 기록을 갱신하도록 예약한다.
  // 매개변수: 없음.
  // 반환값: 없음; 기존 타이머를 취소하고 실행 후 다음 날짜 예약을 만든다.
  void _scheduleDayRefresh() {
    _dayTimer?.cancel();
    final now = MedicationHistoryDates.wallTime(_control.now);
    final tomorrow = _control.today.add(const Duration(days: 1, seconds: 1));
    _dayTimer = Timer(tomorrow.difference(now), () {
      unawaited(_load());
      _scheduleDayRefresh();
    });
  }

  // Function Name: _restorePending
  // Description: Restores pending as-needed intentions before reading or writing records.
  // Parameters: None.
  // Returns: Completion; non-session storage failure sets a write-blocking flag, while invalidated sessions rethrow.
  Future<void> _restorePending() async {
    try {
      await _control.restorePendingAsNeeded();
      _pendingStoreUnavailable = false;
    } catch (_) {
      if (_control.sessionInvalidated) rethrow;
      _pendingStoreUnavailable = true;
    }
  }

  // Function Name: _readToday
  // Description: Loads today's records, removes pending intentions already acknowledged by matching server entries and starts photo loading.
  // Parameters: None.
  // Returns: Completion of record and pending-store updates; errors propagate, and photo loading remains asynchronous.
  Future<void> _readToday() async {
    await _restorePending();
    await _control.load(MedicationHistoryRange(_control.today, _control.today));
    if (!_pendingStoreUnavailable) {
      await _control.removePendingAsNeeded({
        for (final change in _control.pendingAsNeededChanges)
          if (_control.snapshot!.items.any(
            (entry) => entry.key == change.entry.key && entry.revision > 0,
          ))
            change.operationId,
      });
    }
    unawaited(_loadPhotos(_control.snapshot!));
    if (mounted) setState(() {});
  }

  // 함수이름: _loadPhotos
  // 함수역할: 본인 화면의 필요시 약에만 계정별 기기 사진을 조회한다.
  // 매개변수: snapshot: 사진을 읽을 약 목록이 포함된 기록 스냅샷.
  // 반환값: 조회 완료 Future; 읽기 실패는 기본 아이콘으로 대체하고 보호자 화면은 기기 사진을 읽지 않는다.
  Future<void> _loadPhotos(MedicationHistorySnapshot snapshot) async {
    // 기기 전용 사진은 환자 본인의 화면에서만 읽고 보호자는 제공된 원격 사진을 본다.
    if (_readOnly) return;
    for (final medication in snapshot.medications.where(
      (m) => m.dosingMode == 'as_needed',
    )) {
      try {
        final path = await widget.imageStore.findImagePath(
          patientHash: widget.patientHash,
          medicationId: medication.id,
        );
        _control.ensureSession();
        if (!mounted) return;
        _photos[medication.id] = path;
      } catch (_) {
        /* 사진을 읽지 못하면 기존 일정과 같은 기본 약 아이콘을 사용한다. */
      }
    }
    if (mounted) setState(() {});
  }

  // 함수이름: _load
  // 함수역할: 활성 세션에서 오늘 기록을 읽고 중복 작업 중의 갱신 요청은 나중에 다시 실행한다.
  // 매개변수: 없음.
  // 반환값: 현재 조회 시도 완료; 오류 표시는 제어기의 상태에 맡기며 예약된 갱신을 이어 실행한다.
  Future<void> _load() async {
    if (!mounted || !widget.isActive || _control.sessionInvalidated) return;
    if (_recording || _control.busy) {
      _reloadRequested = true;
      return;
    }
    _reloadRequested = false;
    try {
      await _readToday();
    } catch (_) {
      /* 제어 객체가 보관한 오류를 아래 재시도 UI에 표시한다. */
    }
    if (mounted && _reloadRequested) unawaited(_load());
  }

  // 함수이름: _eligible
  // 함수역할: 현재 필요시 복용 기록을 허용하는 약만 선택한다.
  // 매개변수: snapshot: 서버가 반환한 기록·약 목록.
  // 반환값: dosingMode가 as_needed이고 canRecordAsNeeded인 약의 새 목록.
  List<MedicationHistoryMedication> _eligible(
    MedicationHistorySnapshot snapshot,
  ) => snapshot.medications
      .where((m) => m.dosingMode == 'as_needed' && m.canRecordAsNeeded)
      .toList();

  // Function Name: _confirmAdditional
  // Description: Confirms another dose using the displayed count and last-dose time for each selected medication.
  // Parameters: medications: Selected eligible drugs; snapshot: Counts being confirmed.
  // Returns: True only for explicit confirmation; dismissal is false and session invalidation disables recording.
  Future<bool> _confirmAdditional(
    List<MedicationHistoryMedication> medications,
    MedicationHistorySnapshot snapshot,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AnimatedBuilder(
          animation: _control,
          builder: (context, _) => AlertDialog(
            title: Text(tr('추가 복용 기록 확인', 'Confirm another dose')),
            content: SingleChildScrollView(
              child: Text(
                _control.sessionInvalidated
                    ? tr(
                        '로그인 정보가 바뀌었어요. 화면을 다시 열어 주세요.',
                        'Session changed. Reopen this screen.',
                      )
                    : medications
                          .map((m) {
                            final count = _takenCount(snapshot, m.id);
                            final last = _lastTakenText(snapshot, m.id);
                            return tr(
                              '${m.itemName}\n오늘 $count회 → ${count + 1}회로 기록할까요?${last == null ? '' : '\n$last'}',
                              '${m.itemName}\nRecord ${_englishDoses(count + 1)} today instead of $count?${last == null ? '' : '\n$last'}',
                            );
                          })
                          .join('\n\n'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('취소', 'Cancel')),
              ),
              FilledButton(
                key: const Key('prn-confirm-additional'),
                onPressed: _control.sessionInvalidated
                    ? null
                    : () => Navigator.pop(context, true),
                child: Text(tr('기록', 'Record')),
              ),
            ],
          ),
        ),
      ) ==
      true;

  // Function Name: _record
  // Description: Records selected as-needed doses or resumes pending intentions with stable operation IDs.
  // Parameters: medicationId: One medication, or null to prefer not-yet-recorded medicines before adding another dose for all.
  // Returns: Completion with UI feedback; rechecks counts/date after confirmation, blocks unavailable local storage, preserves uncertain requests and offers undo only for this action's current-day records.
  Future<void> _record({int? medicationId}) async {
    if (_readOnly || _locked) return;
    setState(() {
      _recording = true;
      _saveError = null;
    });
    var saved = false;
    final recordedKeys = <String>{};
    var resumedEarlierDay = false;
    try {
      // 다른 화면에서 정정한 횟수를 다시 읽고 확인한 내용만 한 의도로 고정한다.
      await _restorePending();
      if (_pendingStoreUnavailable) {
        _saveError = tr(
          '기기 저장소를 열 수 없어 지금은 기록할 수 없어요. 앱을 다시 시작해 주세요.',
          'Device storage could not be opened, so doses cannot be recorded now. Restart the app.',
        );
        return;
      }
      final resuming = _control.pendingAsNeededChanges.isNotEmpty;
      await _readToday();
      if (!mounted) return;
      _control.ensureSession();
      if (_control.pendingAsNeededChanges.isEmpty && !resuming) {
        final snapshot = _control.snapshot!;
        var medications = _eligible(
          snapshot,
        ).where((m) => medicationId == null || m.id == medicationId).toList();
        if (medicationId == null) {
          final unchecked = medications
              .where((m) => _takenCount(snapshot, m.id) == 0)
              .toList();
          if (unchecked.isNotEmpty) medications = unchecked;
        }
        if (medications.isEmpty) return;
        if (medications.any((m) => _takenCount(snapshot, m.id) > 0)) {
          if (!await _confirmAdditional(medications, snapshot) || !mounted) {
            return;
          }
          _control.ensureSession();
          await _readToday();
          if (!mounted) return;
          final fresh = _control.snapshot!;
          if (fresh.range.end != snapshot.range.end ||
              medications.any(
                (m) =>
                    !_eligible(fresh).any((item) => item.id == m.id) ||
                    _takenCount(fresh, m.id) != _takenCount(snapshot, m.id),
              )) {
            throw const FormatException('Dose count changed.');
          }
        }
        final now = _control.now;
        if (snapshot.range.end != _control.today) {
          throw const FormatException('Date changed.');
        }
        await _control.stageAsNeededChanges(
          medications
              .map(
                (m) => MedicationHistoryChange(
                  entry: MedicationHistoryEntry(
                    medicationId: m.id,
                    itemName: m.itemName,
                    scheduleDate: _control.today,
                    slotKey:
                        'as_needed:${MedicationHistoryControl.newOperationId()}',
                    status: MedicationHistoryStatus.unrecorded,
                    revision: 0,
                    dosingMode: 'as_needed',
                  ),
                  status: MedicationHistoryStatus.taken,
                  operationId: MedicationHistoryControl.newOperationId(),
                  actualTakenAt: now,
                ),
              )
              .toList(),
        );
      }
      // 실행 취소는 이번 동작으로 만든 기록만 되돌리도록 기록 키를 저장 전에 고정한다.
      recordedKeys.addAll(
        _control.pendingAsNeededChanges.map((change) => change.entry.key),
      );
      // 재시작 전에 확인하지 못한 지난날의 기록을 이어 보낸 경우, 이번 탭은 오늘의 새 복용이 아니다.
      resumedEarlierDay = _control.pendingAsNeededChanges.any(
        (change) => change.entry.scheduleDate != _control.today,
      );
      // 일괄 저장 중 일부만 성공해도 남은 요청 ID를 유지해 성공한 약을 중복 기록하지 않는다.
      while (_control.pendingAsNeededChanges.isNotEmpty) {
        final change = _control.pendingAsNeededChanges.first;
        await _control.save(change);
        _control.pendingAsNeededChanges.remove(change);
        saved = true;
        if (!mounted) return;
      }
    } catch (failure) {
      if (failure is ApiRequestException &&
          const {401, 403, 404, 409, 410, 422}.contains(failure.statusCode)) {
        try {
          await _control.removePendingAsNeeded(
            _control.pendingAsNeededChanges
                .map((change) => change.operationId)
                .toSet(),
          );
        } catch (_) {
          // 저장소나 계정이 바뀌면 미확인 의도를 지운 것으로 처리하지 않는다.
        }
      }
      if (mounted && !_control.sessionInvalidated) {
        _saveError = _control.pendingAsNeededChanges.isEmpty
            ? tr(
                '목록이나 횟수가 바뀌었거나 연결하지 못했어요. 확인 후 다시 눌러 주세요.',
                'The list changed or could not be loaded. Check and try again.',
              )
            : tr(
                '저장 결과를 확인하지 못했어요. 체크를 다시 누르면 같은 기록으로 확인합니다.',
                'Save could not be confirmed. Tap the check again to retry the same record.',
              );
      }
    } finally {
      if (mounted) {
        setState(() => _recording = false);
        // 취소했어도 응답 유실 뒤 닫았을 수 있으므로 서버 상태를 다시 확인한다.
        final hadPending = _control.pendingAsNeededChanges.isNotEmpty;
        await _load();
        if (mounted &&
            hadPending &&
            _control.pendingAsNeededChanges.isEmpty &&
            _control.snapshot != null) {
          setState(() => _saveError = null);
          saved = true;
        }
      }
    }
    if (mounted &&
        saved &&
        _saveError == null &&
        !_control.sessionInvalidated) {
      // 안내는 앱 전체 메신저에 떠 일정 화면을 떠난 뒤에도 남으므로, 결과도 같은 메신저로 알린다.
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        resumedEarlierDay
            // 지난날 기록은 오늘 목록에서 되돌릴 수 없으므로 실행 취소 대신 다시 누르라고 알린다.
            ? SnackBar(
                key: const Key('prn-earlier-record-sent'),
                content: Text(
                  tr(
                    '이전에 저장하지 못한 복용 기록을 보냈어요. 오늘 복용했다면 다시 눌러 기록해 주세요.',
                    'A dose that could not be saved earlier was sent. If you took one today, tap again to record it.',
                  ),
                ),
                duration: const Duration(seconds: 6),
              )
            : SnackBar(
                content: Text(tr('복용 기록을 저장했어요.', 'Dose recorded.')),
                duration: const Duration(seconds: 5),
                persist: false,
                action: SnackBarAction(
                  key: const Key('prn-undo-record'),
                  label: tr('실행 취소', 'Undo'),
                  onPressed: () => unawaited(_undo(recordedKeys, messenger)),
                ),
              ),
      );
    }
  }

  // Function Name: _undo
  // Description: Re-reads today's records and changes matching still-taken as-needed entries back to unrecorded.
  // Parameters: keys: Record identities created by this action; messenger: Original feedback host.
  // Returns: Completion with feedback; a shared controller permits undo after leaving the screen, but a screen-owned disposed controller does not. Already delivered caregiver alerts are not retracted.
  Future<void> _undo(Set<String> keys, ScaffoldMessengerState messenger) async {
    if ((!mounted && widget.control == null) ||
        _readOnly ||
        _locked ||
        keys.isEmpty) {
      return;
    }
    // Function Name: update
    // Description: Applies an undo-state change with a rebuild only while the widget remains mounted.
    // Parameters: change: Synchronous state mutation.
    // Returns: None; after navigation, the mutation runs without setState.
    void update(VoidCallback change) => mounted ? setState(change) : change();
    update(() {
      _recording = true;
      _saveError = null;
    });
    var undone = false;
    String? failure;
    try {
      await _readToday();
      final entries = _control.snapshot!.items
          .where(
            (entry) =>
                keys.contains(entry.key) &&
                entry.isAsNeeded &&
                entry.status == MedicationHistoryStatus.taken,
          )
          .toList();
      for (final entry in entries) {
        await _control.save(
          MedicationHistoryChange(
            entry: entry,
            status: MedicationHistoryStatus.unrecorded,
            operationId: MedicationHistoryControl.newOperationId(),
          ),
        );
        undone = true;
      }
    } catch (_) {
      if (!_control.sessionInvalidated) {
        failure = tr(
          '복용 기록을 취소하지 못했어요. 복약 기록에서 해당 기록을 \'미기록\'으로 바꿔 주세요.',
          'The dose could not be undone. Change it to "Not recorded" in the dose history.',
        );
      }
    } finally {
      update(() {
        _recording = false;
        if (mounted) _saveError = failure;
      });
      if (mounted) await _load();
    }
    if (_control.sessionInvalidated || (failure == null && !undone)) return;
    // 화면에 남아 있으면 실패는 카드에 보이고, 떠난 뒤라면 안내로만 알릴 수 있다.
    if (failure != null && mounted) return;
    if (mounted && _saveError != null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(failure ?? tr('복용 기록을 취소했어요.', 'Dose record undone.')),
        duration: Duration(seconds: failure == null ? 2 : 6),
      ),
    );
  }

  // Function Name: _configureReminder
  // Description: Opens a one-time check-reminder editor after checking ownership, permissions and concurrent work.
  // Parameters: None.
  // Returns: Completion after the dialog closes; save failures stay in the dialog and past clock selections advance to tomorrow.
  Future<void> _configureReminder() async {
    if (_readOnly || _reminderOpen || _locked || _reminder.busy) return;
    if (!widget.notificationsAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              '환경설정에서 복약 알림을 먼저 켜 주세요.',
              'Enable medication notifications in Settings first.',
            ),
          ),
        ),
      );
      return;
    }
    _reminderOpen = true;
    var enabled = _reminder.enabled;
    var selected =
        _reminder.scheduledAt ?? _control.now.add(const Duration(hours: 1));
    String? error;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AnimatedBuilder(
            animation: _control,
            builder: (context, _) => AlertDialog(
              title: Text(tr('필요시 약 확인 알림', 'As-needed check reminder')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('확인 알림', 'Check reminder')),
                      value: enabled,
                      onChanged: _reminder.busy || _control.sessionInvalidated
                          ? null
                          : (value) => update(() => enabled = value),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: Text(MedicationHistoryDates.timestamp(selected)),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: _reminder.busy || _control.sessionInvalidated
                          ? null
                          : () async {
                              final wall = MedicationHistoryDates.wallTime(
                                selected,
                              );
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: wall.hour,
                                  minute: wall.minute,
                                ),
                              );
                              if (time == null || !context.mounted) return;
                              var date = MedicationHistoryDates.instant(
                                _control.today,
                                time.hour,
                                time.minute,
                              );
                              if (!date.isAfter(_control.now)) {
                                date = date.add(const Duration(days: 1));
                              }
                              update(() => selected = date);
                            },
                    ),
                    Text(
                      tr(
                        '선택한 시각에 한 번만 알려드려요. 복용 지시나 미복용 경고는 보내지 않습니다.',
                        'One check at the selected time, without missed-dose warnings or repeat reminders.',
                      ),
                    ),
                    if (error != null)
                      Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _reminder.busy
                      ? null
                      : () => Navigator.pop(context),
                  child: Text(tr('취소', 'Cancel')),
                ),
                FilledButton(
                  key: const Key('prn-reminder-save'),
                  onPressed: _reminder.busy || _control.sessionInvalidated
                      ? null
                      : () async {
                          final future = _reminder.save(
                            enabled ? selected : null,
                            isEnglish: widget.isEnglish,
                          );
                          update(() => error = null);
                          try {
                            await future;
                            if (context.mounted) Navigator.pop(context);
                          } catch (_) {
                            if (context.mounted) {
                              update(
                                () => error = tr(
                                  '알림을 저장하지 못했어요. 알림 권한과 시각을 확인해 주세요.',
                                  'Could not save. Check notification permission and time.',
                                ),
                              );
                            }
                          }
                        },
                  child: Text(tr('저장', 'Save')),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      _reminderOpen = false;
      if (mounted) setState(() {});
    }
  }

  // 함수이름: dispose
  // 함수역할: 날짜 타이머와 생명주기 구독을 제거하고 화면이 만든 제어기만 해제한다.
  // 매개변수: 없음.
  // 반환값: 없음; 주입된 기록·알림 제어기는 유지한다.
  @override
  void dispose() {
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.control == null) _control.dispose();
    if (widget.reminderControl == null) _reminder.dispose();
    super.dispose();
  }

  // 함수이름: build
  // 함수역할: 필요시 약의 오늘 횟수와 대기 기록·오류·알림 조작을 제어기 변경에 맞춰 표시한다.
  // 매개변수: context: 화면 구성 문맥.
  // 반환값: 기록 영역 또는 최초 로딩·빈 화면; 재조회 중에는 같은 날짜의 이전 목록을 유지하고 보호자 조작을 제한한다.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _control,
    builder: (context, _) {
      if (_control.sessionInvalidated || _control.error != null) {
        _lastSnapshot = null;
      } else if (_control.snapshot != null) {
        _lastSnapshot = _control.snapshot;
      }
      // 저장 직후 재조회 동안 카드 높이를 유지해 목록이 위로 튀지 않도록 한다.
      final snapshot =
          _control.snapshot ??
          (_lastSnapshot?.range.end == _control.today ? _lastSnapshot : null);
      final pending = _control.pendingAsNeededChange;
      final medications = snapshot == null
          ? <MedicationHistoryMedication>[]
          : _eligible(snapshot);
      for (final change in _control.pendingAsNeededChanges) {
        if (!medications.any((m) => m.id == change.entry.medicationId) &&
            snapshot != null) {
          medications.add(
            snapshot.medications
                    .where((m) => m.id == change.entry.medicationId)
                    .firstOrNull ??
                MedicationHistoryMedication(
                  id: change.entry.medicationId,
                  itemName: change.entry.itemName,
                  dosingMode: 'as_needed',
                ),
          );
        }
      }
      // 첫 조회 전에는 빈 필요시 복용 카드와 조작 버튼 대신 로딩만 표시한다.
      // 이후 재조회는 기존 스냅샷을 유지해 복용 체크마다 카드가 사라지지 않게 한다.
      // 이전 결과가 비어 있으면 재조회 중에도 빈 카드 대신 로딩을 유지한다.
      if (widget.isActive &&
          _control.error == null &&
          (snapshot == null || (_control.busy && medications.isEmpty))) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: CircularProgressIndicator(
              key: Key('schedule-prn-initial-loading'),
              color: MedBuddyColors.primary,
            ),
          ),
        );
      }
      if (!_control.busy && _control.error == null && medications.isEmpty) {
        return widget.emptyState;
      }
      final style = MedBuddySlotStyle.of('as_needed');
      final allChecked =
          medications.isNotEmpty &&
          medications.every((m) => _takenCount(snapshot!, m.id) > 0);
      final reminderOn = _reminder.enabled && widget.notificationsAllowed;
      return Material(
        key: const Key('schedule-as-needed'),
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: MedBuddyRadii.card,
          side: const BorderSide(color: MedBuddyColors.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MedicationSlotHeaderStrip(
              style: style,
              title: tr('필요시 복용', 'As-needed medication'),
              status: _readOnly
                  ? widget.readOnlyStatusLabel ??
                        tr('환자가 기록한 복용 내역', 'Patient-reported doses')
                  : reminderOn
                  ? tr(
                      '확인 알림 ${MedicationHistoryDates.timestamp(_reminder.scheduledAt)}',
                      'Check ${MedicationHistoryDates.timestamp(_reminder.scheduledAt)}',
                    )
                  : tr('확인 알림 꺼짐', 'Check reminder off'),
              trailing: [
                if (_readOnly && widget.readOnlyHeaderAction != null)
                  widget.readOnlyHeaderAction!,
                if (!_readOnly) ...[
                  IconButton(
                    key: const Key('prn-reminder'),
                    tooltip: tr('필요시 약 알림 설정', 'As-needed reminder settings'),
                    onPressed: _locked ? null : _configureReminder,
                    style: IconButton.styleFrom(
                      backgroundColor: reminderOn
                          ? Colors.white
                          : Colors.transparent,
                    ),
                    icon: Icon(
                      reminderOn
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_none_outlined,
                      color: reminderOn
                          ? const Color(0xFFFF1744)
                          : MedBuddyColors.textSubtle,
                      size: 29,
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    key: const Key('schedule-entire-slot-toggle-as_needed'),
                    tooltip: pending != null
                        ? tr('저장 결과 확인', 'Check pending doses')
                        : allChecked
                        ? tr('필요시 약 추가 복용 기록', 'Record another dose for all')
                        : tr(
                            '필요시 약 전부 체크',
                            'Mark unchecked as-needed medicines taken',
                          ),
                    onPressed: _locked || medications.isEmpty
                        ? null
                        : () => _record(),
                    style: IconButton.styleFrom(
                      backgroundColor: allChecked
                          ? style.color
                          : Colors.transparent,
                      foregroundColor: allChecked ? Colors.white : style.color,
                      side: BorderSide(color: style.color, width: 1.5),
                    ),
                    icon: const Icon(Icons.done_all_rounded, size: 24),
                  ),
                ],
              ],
            ),
            if (_control.busy) const LinearProgressIndicator(),
            if (_control.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      _control.sessionInvalidated
                          ? tr(
                              '로그인 정보가 바뀌었어요. 화면을 다시 열어 주세요.',
                              'Session changed. Reopen this screen.',
                            )
                          : tr(
                              '필요시 약을 불러오지 못했어요. 연결을 확인해 주세요.',
                              'Could not load as-needed medication. Check your connection.',
                            ),
                      key: const Key('schedule-prn-error'),
                    ),
                    IconButton(
                      tooltip: tr('필요시 약 새로고침', 'Refresh as-needed medication'),
                      onPressed: _locked ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_saveError!, key: const Key('prn-save-error')),
              ),
            for (var i = 0; i < medications.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, color: MedBuddyColors.cardBorder),
              _row(medications[i], snapshot!, pending),
            ],
          ],
        ),
      );
    },
  );

  // 함수이름: _row
  // 함수역할: 약 한 건의 오늘 횟수·용량·사진과 기록 조작을 표시한다.
  // 매개변수: medication: 표시 약; snapshot: 오늘 기록; pending: 미확인 저장 의도.
  // 반환값: 약 행 위젯; 읽기 전용이면 기록 버튼을 숨기고 다른 약의 미확인 저장 중에는 조작을 막는다.
  Widget _row(
    MedicationHistoryMedication medication,
    MedicationHistorySnapshot snapshot,
    MedicationHistoryChange? pending,
  ) {
    final count = _takenCount(snapshot, medication.id);
    final checked = count > 0;
    final photo = _photos[medication.id] ?? '';
    return Padding(
      padding: EdgeInsets.fromLTRB(_readOnly ? 18 : 6, 8, 14, 8),
      child: Row(
        children: [
          if (!_readOnly) ...[
            Semantics(
              checked: checked,
              button: true,
              child: IconButton(
                key: ValueKey('schedule-prn-take-${medication.id}'),
                tooltip: pending != null
                    ? tr('저장 결과 확인', 'Check pending doses')
                    : checked
                    ? tr('추가 복용 기록', 'Record another dose')
                    : tr('복용 완료', 'Mark taken'),
                onPressed:
                    _locked ||
                        (pending != null &&
                            pending.entry.medicationId != medication.id)
                    ? null
                    : () => _record(medicationId: medication.id),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(
                  checked ? Icons.check_circle_outline : Icons.circle_outlined,
                  size: 25,
                  color: checked
                      ? MedBuddyColors.primary
                      : MedBuddyColors.outline,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medication.itemName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: checked
                        ? MedBuddyColors.textLight
                        : MedBuddyColors.textStrong,
                    decoration: checked ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (medication.dosage.isNotEmpty)
                  Text(
                    localizedDoseAmountLabel(
                      medication.dosage,
                      widget.isEnglish ? 'en' : 'ko',
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      color: MedBuddyColors.textMuted,
                    ),
                  ),
                Text(
                  tr('오늘 $count회', '${_englishDoses(count)} today'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: MedBuddyColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          MedicationThumbnail(
            key: ValueKey('schedule-prn-thumbnail-${medication.id}'),
            imageUrl: medication.imageUrl,
            localImagePath: photo,
            tooltip: medication.itemName,
            onTap: () => MedicationImageViewer.show(
              context,
              medicationName: medication.itemName,
              imageUrl: medication.imageUrl,
              localImagePath: photo,
              language: widget.isEnglish ? 'en' : 'ko',
            ),
          ),
        ],
      ),
    );
  }

  // Function Name: _lastTakenText
  // Description: Formats the latest taken record's clock time and elapsed duration using the configured history timezone.
  // Parameters: snapshot: Current-day records; medicationId: Target medication.
  // Returns: Localized last-dose guidance, or null without a usable taken timestamp; actual intake time takes precedence over recorded time.
  String? _lastTakenText(MedicationHistorySnapshot snapshot, int medicationId) {
    DateTime? last;
    for (final entry in snapshot.items) {
      if (entry.medicationId != medicationId ||
          !entry.isAsNeeded ||
          entry.status != MedicationHistoryStatus.taken) {
        continue;
      }
      final time = entry.actualTakenAt ?? entry.recordedAt;
      if (time != null && (last == null || time.isAfter(last))) last = time;
    }
    if (last == null) return null;
    final clock = MedicationHistoryDates.clock(last);
    final elapsed = _control.now.difference(last);
    if (elapsed.isNegative) {
      return tr('마지막 복용 $clock', 'Last dose at $clock');
    }
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes % 60;
    final ago = hours > 0
        ? tr(
            minutes > 0 ? '$hours시간 $minutes분 전' : '$hours시간 전',
            minutes > 0 ? '$hours h $minutes min ago' : '$hours h ago',
          )
        : elapsed.inMinutes < 1
        // 1분이 안 됐으면 "0분 전" 대신 "방금 전"으로 적는다.
        ? tr('방금 전', 'just now')
        : tr('${elapsed.inMinutes}분 전', '${elapsed.inMinutes} min ago');
    return tr('마지막 복용 $clock ($ago)', 'Last dose at $clock ($ago)');
  }

  // 함수이름: _takenCount
  // 함수역할: 스냅샷에서 지정 약의 필요시 복용 완료 기록 수를 센다.
  // 매개변수: snapshot: 집계할 기록; medicationId: 약 ID.
  // 반환값: 필요시이며 taken인 항목 수; 다른 상태는 제외한다.
  int _takenCount(MedicationHistorySnapshot snapshot, int medicationId) =>
      snapshot.items
          .where(
            (entry) =>
                entry.medicationId == medicationId &&
                entry.isAsNeeded &&
                entry.status == MedicationHistoryStatus.taken,
          )
          .length;
}

// Function Name: _englishDoses
// Description: Formats an English dose count with singular or plural units.
// Parameters: count: Number of dose records.
// Returns: 1 dose only for one, otherwise the count followed by doses.
String _englishDoses(int count) => count == 1 ? '1 dose' : '$count doses';
