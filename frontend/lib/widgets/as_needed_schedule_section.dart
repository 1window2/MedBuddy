// 필요시 약의 새 복용은 일정에서 기록하고 기존 보고의 정정은 복약 기록에 맡긴다.
import 'dart:async';
import 'package:flutter/material.dart';
import '../boundaries/medication_image_viewer_boundary.dart';
import '../controls/as_needed_check_reminder_control.dart';
import '../controls/medication_history_control.dart';
import '../entities/medication_history_entity.dart';
import '../services/manual_medication_image_store.dart';
import '../services/api_response_parser.dart';
import '../theme/medbuddy_theme.dart';
import 'medication_thumbnail.dart';

class AsNeededScheduleSection extends StatefulWidget {
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
  @override
  State<AsNeededScheduleSection> createState() =>
      _AsNeededScheduleSectionState();
}

class _AsNeededScheduleSectionState extends State<AsNeededScheduleSection>
    with WidgetsBindingObserver {
  late final MedicationHistoryControl _control;
  late final AsNeededCheckReminderControl _reminder;
  Timer? _dayTimer;
  bool _recording = false;
  bool _reminderOpen = false;
  bool _reloadRequested = false;
  MedicationHistorySnapshot? _lastSnapshot;
  final Map<int, String> _photos = {};
  String? _saveError;
  String tr(String ko, String en) => widget.isEnglish ? en : ko;
  bool get _readOnly => widget.readOnly || _control.readOnly;
  bool get _locked =>
      _recording || _control.busy || _control.sessionInvalidated;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleDayRefresh();
      unawaited(_load());
      unawaited(_restoreReminder());
    }
  }

  // 한국 날짜가 바뀌면 전날의 복용 가능 목록과 횟수를 계속 보여주지 않는다.
  void _scheduleDayRefresh() {
    _dayTimer?.cancel();
    final now = MedicationHistoryDates.wallTime(_control.now);
    final tomorrow = _control.today.add(const Duration(days: 1, seconds: 1));
    _dayTimer = Timer(tomorrow.difference(now), () {
      unawaited(_load());
      _scheduleDayRefresh();
    });
  }

  Future<void> _readToday() async {
    await _control.load(MedicationHistoryRange(_control.today, _control.today));
    _control.pendingAsNeededChanges.removeWhere(
      (change) => _control.snapshot!.items.any(
        (entry) => entry.key == change.entry.key && entry.revision > 0,
      ),
    );
    unawaited(_loadPhotos(_control.snapshot!));
    if (mounted) setState(() {});
  }

  // 사진의 기기 저장소 조회 때문에 복용 체크를 기다리게 하지 않는다.
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

  List<MedicationHistoryMedication> _eligible(
    MedicationHistorySnapshot snapshot,
  ) => snapshot.medications
      .where((m) => m.dosingMode == 'as_needed' && m.canRecordAsNeeded)
      .toList();

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
                            return tr(
                              '${m.itemName}\n오늘 $count회 → ${count + 1}회로 기록할까요?',
                              '${m.itemName}\nRecord ${count + 1} doses today instead of $count?',
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

  Future<void> _record({int? medicationId}) async {
    if (_readOnly || _locked) return;
    setState(() {
      _recording = true;
      _saveError = null;
    });
    var saved = false;
    try {
      // 다른 화면에서 정정한 횟수를 다시 읽고 확인한 내용만 한 의도로 고정한다.
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
        _control.pendingAsNeededChanges.addAll(
          medications.map(
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
          ),
        );
      }
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
          const {401, 403, 404, 409, 422}.contains(failure.statusCode)) {
        _control.pendingAsNeededChanges.clear();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('복용 기록을 저장했어요.', 'Dose recorded.'))),
      );
    }
  }

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
                              final today = _control.today;
                              var date = DateTime.utc(
                                today.year,
                                today.month,
                                today.day,
                                time.hour,
                                time.minute,
                              ).subtract(const Duration(hours: 9));
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

  @override
  void dispose() {
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.control == null) _control.dispose();
    if (widget.reminderControl == null) _reminder.dispose();
    super.dispose();
  }

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
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              decoration: BoxDecoration(
                color: style.tint,
                border: Border(left: BorderSide(color: style.color, width: 5)),
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
                    child: const Icon(
                      Icons.medication_outlined,
                      color: Colors.white,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('필요시 복용', 'As-needed medication'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _readOnly
                              ? widget.readOnlyStatusLabel ??
                                    tr(
                                      '환자가 기록한 복용 내역',
                                      'Patient-reported doses',
                                    )
                              : reminderOn
                              ? tr(
                                  '확인 알림 ${MedicationHistoryDates.timestamp(_reminder.scheduledAt)}',
                                  'Check ${MedicationHistoryDates.timestamp(_reminder.scheduledAt)}',
                                )
                              : tr('확인 알림 꺼짐', 'Check reminder off'),
                          style: TextStyle(
                            color: style.color,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                        foregroundColor: allChecked
                            ? Colors.white
                            : style.color,
                        side: BorderSide(color: style.color, width: 1.5),
                      ),
                      icon: const Icon(Icons.done_all_rounded, size: 24),
                    ),
                  ],
                ],
              ),
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
                    medication.dosage,
                    style: const TextStyle(
                      fontSize: 14,
                      color: MedBuddyColors.textMuted,
                    ),
                  ),
                Text(
                  tr('오늘 $count회', '$count doses today'),
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
