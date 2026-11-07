// 파일명: dose_sync_service.dart
// 역할: 복용 변경을 기기에 먼저 저장하고 계정별 순서대로 서버에 재전송한다.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../entities/dose_widget_state.dart';
import '../entities/medication_schedule_entity.dart';
import '../entities/offline_schedule_window.dart';
import 'api_config.dart';
import 'dose_outbox_store.dart';

// Function Name: doseScheduleDay
// Description: Uses the shared widget/server clock instead of the display timezone.
// Parameters: now (DateTime) - instant to assign to a dose day.
// Returns: YYYY-MM-DD in the configured dose timezone, UTC+09:00 by default.
String doseScheduleDay(DateTime now) => doseWidgetDay(now);

// Function Name: projectDoseOperations
// Description: Overlays pending dose changes in queue order onto matching server schedules without mutating them.
// Parameters: schedules (List<MedicationSchedule>) - confirmed courses; operations (List<Map<String, dynamic>>) - oldest first;
// - scheduleDay (String): YYYY-MM-DD to project. Operations must have the validated outbox payload shape.
// Returns: Copied schedules with matching medication/slot statuses and aggregate completion recalculated; other days are ignored.
List<MedicationSchedule> projectDoseOperations(
  List<MedicationSchedule> schedules,
  List<Map<String, dynamic>> operations,
  String scheduleDay,
) {
  return schedules.map((schedule) {
    final statuses = {
      for (final slot in schedule.slotKeys)
        slot: schedule.isSlotCompleted(slot),
    };
    for (final op in operations) {
      if (op['schedule_date'] == scheduleDay &&
          (op['medication_ids'] as List).contains(
            int.tryParse(schedule.medicationID),
          )) {
        statuses[op['slot_key'] as String] = op['completed'] as bool;
      }
    }
    return schedule.copyWith(
      slotStatuses: statuses,
      medicationStatus:
          statuses.isNotEmpty && statuses.values.every((value) => value),
    );
  }).toList();
}

// Function Name: withoutChatReceipt
// Description: Removes the chat side effect while retaining the dose change, using a derived ID to avoid reusing an accepted ID with another body.
// Parameters: operation (Map<String, dynamic>) - queued payload with a string operation_id.
// Returns: A copy without link_id whose operation_id ends in _nochat; the input is unchanged.
Map<String, dynamic> withoutChatReceipt(Map<String, dynamic> operation) {
  final id = operation['operation_id'] as String;
  return {...operation, 'operation_id': '${id}_nochat'}..remove('link_id');
}

// Class Name: DoseSyncService
// Role: Coordinates one account's durable dose queue, schedule cache, and foreground retries.
// Responsibilities:
// - Persist dose changes before upload, preserve per-dose ordering, and publish confirmed and pending state separately.
// - Reject obsolete cache windows and stop session-owned work after disposal.
// Attributes:
// - owner (String), client (http.Client): Account scope and caller-owned transport.
// - openStore, scheduleWork, clock: Injected storage, background scheduling, and time providers.
// - onStateChanged, loadScheduleWindow: Optional display publisher and offline-course loader.
// - _operations, _confirmed, _cacheDate: Pending changes and the dated authoritative snapshot.
// - _disposed, _foreground, _timer: Session lifetime and retry scheduling state.
class DoseSyncService extends ChangeNotifier with WidgetsBindingObserver {
  final String owner;
  final http.Client client;
  final Future<DoseOutboxStore> Function() openStore;
  final Future<void> Function() scheduleWork;
  final DateTime Function() clock;
  final Future<void> Function()? onStateChanged;
  final Future<List<MedicationSchedule>> Function()? loadScheduleWindow;
  Future<void>? _refreshingWindow;
  bool _windowRefreshAgain = false;
  DoseOutboxStore? _store;
  Future<void>? _initializing;
  bool _activationRequested = false;
  Future<void>? _draining;
  bool _publishing = false;
  bool _publishAgain = false;
  Timer? _timer;
  bool _disposed = false;
  bool _foreground = true;
  bool _observing = false;
  int _retry = 0;
  List<Map<String, dynamic>> _operations = const [];
  // 외부에서는 읽기만 하고 값은 이 객체만 바꾼다.
  // Function Name: operations
  // Description: Exposes the latest queue snapshot for pending/rejected dose presentation.
  // Parameters: None.
  // Returns: The current list, not a defensive copy; callers must not mutate it.
  List<Map<String, dynamic>> get operations => _operations;
  // 기기 키가 사라져 전송하지 못하고 버려진 기록 수. 사용자가 확인할 때까지 유지한다.
  int _lostRecordCount = 0;
  // Function Name: lostRecordCount
  // Description: Exposes unreadable records lost after encryption-key recovery until acknowledged.
  // Parameters: None.
  // Returns: The account's last loaded loss count.
  int get lostRecordCount => _lostRecordCount;
  // 서버가 받은 기록 수. 서버 기록을 보여 주는 화면이 다시 읽을 때를 알려 준다.
  int _acceptedRevision = 0;
  // Function Name: acceptedRevision
  // Description: Provides an in-memory receipt counter so history views can detect accepted uploads.
  // Parameters: None.
  // Returns: Successful acknowledgements observed by this service, not the store cache revision.
  int get acceptedRevision => _acceptedRevision;
  List<MedicationSchedule> _confirmed = const [];
  String _cacheDate = '';
  String _fingerprint = '';

  // 함수이름: DoseSyncService
  // 함수역할: 계정별 동기화 의존성을 보관한다. 생성만으로 저장소를 열거나 전송하지 않는다.
  // 매개변수:
  // - owner (String), client (http.Client): 계정 키와 호출자가 수명을 관리하는 HTTP 연결
  // - openStore, scheduleWork: 저장소 열기와 백그라운드 작업 예약 함수. 미지정 예약은 아무 작업도 하지 않는다.
  // - clock (DateTime Function()?): 날짜·재시도 기준 시계. 기본값은 DateTime.now
  // - onStateChanged, loadScheduleWindow: 선택적 표시 갱신 함수와 오프라인 기간 일정 로더
  // 반환값: 아직 시작되지 않은 DoseSyncService.
  DoseSyncService({
    required this.owner,
    required this.client,
    Future<DoseOutboxStore> Function()? openStore,
    Future<void> Function()? scheduleWork,
    DateTime Function()? clock,
    this.onStateChanged,
    this.loadScheduleWindow,
  }) : openStore = openStore ?? DoseOutboxStore.open,
       scheduleWork = scheduleWork ?? (() async {}),
       clock = clock ?? DateTime.now;

  // Function Name: hasScheduledRetry
  // Description: Makes foreground retry scheduling observable in tests.
  // Parameters: None.
  // Returns: True only while the next retry timer remains active.
  @visibleForTesting
  bool get hasScheduledRetry => _timer?.isActive ?? false;

  // Function Name: pendingCount
  // Description: Counts the loaded queue, including server-rejected records awaiting a decision.
  // Parameters: None.
  // Returns: Number of pending-list entries, not only uploadable entries.
  int get pendingCount => _operations.length;
  // Function Name: hasBlocked
  // Description: Detects whether any loaded record needs explicit retry or dismissal after rejection.
  // Parameters: None.
  // Returns: True when at least one operation has state blocked.
  bool get hasBlocked => _operations.any((op) => op['state'] == 'blocked');
  // 함수이름: hasCache
  // 함수역할: 마지막 캐시가 현재 복약 기준일의 것인지 확인한다.
  // 매개변수: 없음.
  // 반환값: 캐시 날짜가 오늘과 같으면 true. 목록이 비어 있어도 날짜가 맞으면 유효하다.
  bool get hasCache => _cacheDate == doseScheduleDay(clock());
  // 함수이름: schedules
  // 함수역할: 오늘 유효한 서버 일정에 대기 중 복용 변경을 반영한다.
  // 매개변수: 없음.
  // 반환값: 표시할 일정 목록. 오늘 캐시가 없으면 빈 목록.
  List<MedicationSchedule> get schedules =>
      project(hasCache ? _confirmed : const []);

  // 함수이름: initialize
  // 함수역할: 저장소 초기화를 공유하고 실패한 호출은 다음 요청에서 재시도할 수 있게 한다.
  // 매개변수: activate (bool) - 초기화 시 이 계정을 활성화할지 여부. 재시도에도 요청을 유지한다.
  // 반환값: 초기화·재조회 완료 Future. 저장소 오류는 전파하며 완료된 초기화를 다시 실행하지 않는다.
  Future<void> initialize({bool activate = false}) {
    // 첫 열기가 실패한 뒤의 재시도도 처음 요청한 계정 활성화를 수행해야 한다.
    _activationRequested = _activationRequested || activate;
    return _initializing ??= _initialize(_activationRequested).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      // 일시적인 저장소 오류 뒤에도 다음 요청에서 다시 열 수 있게 한다.
      _initializing = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  // 함수이름: _initialize
  // 함수역할: 저장소를 연 뒤 살아 있는 세션만 활성 계정을 바꾸고 캐시를 읽는다.
  // 매개변수: activate (bool) - 이 계정의 활성화 필요 여부
  // 반환값: 초기화 완료 Future. 열기·활성화 도중 dispose되면 후속 작업을 중단하고 저장소 오류는 전파한다.
  Future<void> _initialize(bool activate) async {
    _store = await openStore();
    if (_disposed) return;
    if (activate) {
      await _store!.activate(owner, isCurrent: () => !_disposed);
    }
    if (_disposed) return;
    await reload();
  }

  // 함수이름: start
  // 함수역할: 계정을 초기화하고 앱 상태 감시·백그라운드 예약·첫 전송을 시작한다.
  // 매개변수: 없음. 같은 인스턴스의 시작은 소유자가 한 번 요청한다.
  // 반환값: 초기화와 예약 요청 완료 Future. 실제 전송 완료는 기다리지 않으며 초기화 오류는 전파한다.
  Future<void> start() async {
    await initialize(activate: true);
    if (_disposed) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(scheduleWork().catchError((_) {}));
    unawaited(drain());
    _scheduleRetry();
  }

  // 함수이름: reload
  // 함수역할: 오프라인 오늘 일정을 준비하고 캐시·전송 대기·유실 건수를 다시 읽어 달라진 상태만 알린다.
  // 매개변수: 없음. initialize로 저장소가 열린 상태여야 한다.
  // 반환값: 읽기와 표시 갱신 요청 완료 Future. 저장소 오류는 전파한다.
  Future<void> reload() async {
    await prepareOfflineCache(_store!, owner: owner, now: clock());
    final cache = await _store!.readCache(owner);
    _cacheDate = (await _store!.isActive(owner))
        ? (cache?['date'] as String? ?? '')
        : '';
    _confirmed = MedicationSchedule.fromScheduleJsonList(cache?['schedules']);
    _operations = await _store!.pending(owner);
    _lostRecordCount = await _store!.lostOperationCount(owner);
    final fingerprint = _stateFingerprint(cache);
    if (fingerprint != _fingerprint) {
      _fingerprint = fingerprint;
      if (!_disposed) notifyListeners();
      await _publishState();
    }
  }

  // Function Name: _stateFingerprint
  // Description: Detects presentation changes across the dose day, cache, queue, and loss count.
  // Parameters: cache (Map<String, dynamic>?) - last stored authoritative snapshot.
  // Returns: JSON comparison key; values must remain JSON-encodable.
  String _stateFingerprint(Map<String, dynamic>? cache) => jsonEncode([
    doseScheduleDay(clock()),
    cache,
    _operations,
    _lostRecordCount,
  ]);

  // 함수이름: cacheRevision
  // 함수역할: 비동기 조회 시작 시 오래된 응답 저장을 막을 현재 계정 캐시 버전을 읽는다.
  // 매개변수: 없음.
  // 반환값: 저장된 버전 번호 Future. 초기화·저장소 오류는 전파한다.
  Future<int> cacheRevision() async {
    await initialize();
    return _store!.cacheRevision(owner);
  }

  // 앱과 위젯이 같은 기간·복용 주기 규칙으로 오늘 일정을 만든다.
  // 함수이름: prepareOfflineCache
  // 함수역할: 검증된 기간 일정에서 해당 복약 날짜의 일정을 투영하도록 저장소에 요청한다.
  // 매개변수: store (DoseOutboxStore) - 열린 저장소; owner (String?) - 계정, null이면 활성 계정; now (DateTime) - 기준 시각.
  // 반환값: 저장소 갱신 완료 Future. 유효 기간 밖의 일정은 투영하지 않으며 저장소 오류는 전파한다.
  static Future<void> prepareOfflineCache(
    DoseOutboxStore store, {
    String? owner,
    required DateTime now,
  }) => store.prepareOfflineScheduleDay(
    owner: owner,
    day: doseScheduleDay(now),
    project: (window) => OfflineScheduleWindow.project(
      window,
      doseScheduleDay(now),
    )?.map((course) => course.toJson()).toList(),
  );

  // 함수이름: refreshScheduleWindow
  // 함수역할: 동시에 들어온 기간 갱신을 공유하고 진행 중 추가 요청은 완료 뒤 한 번 더 실행한다.
  // 매개변수: 없음.
  // 반환값: 현재 갱신 완료 Future. 뒤에 예약한 재갱신까지 기다리는 것은 아니다.
  Future<void> refreshScheduleWindow() {
    final pending = _refreshingWindow;
    if (pending != null) {
      _windowRefreshAgain = true;
      return pending;
    }
    return _refreshingWindow = _refreshScheduleWindow().whenComplete(() {
      _refreshingWindow = null;
      if (_windowRefreshAgain && !_disposed) {
        _windowRefreshAgain = false;
        unawaited(refreshScheduleWindow());
      }
    });
  }

  // 함수이름: invalidateSchedule
  // 함수역할: 처방 변경 후 오늘·기간 캐시를 무효화하고 표시 상태를 다시 읽는다.
  // 매개변수: 없음.
  // 반환값: 무효화·재조회 완료 Future. 저장소 오류는 전파한다.
  Future<void> invalidateSchedule() async {
    await initialize();
    await _store!.invalidateDoseSchedules(owner);
    await reload();
  }

  // 처방 변경 요청 전에 일정을 비우되 되돌릴 수 있게 보관한다.
  // Function Name: suspendSchedule
  // Description: Temporarily removes dose schedules before a regimen write and publishes the cleared state.
  // Parameters: None.
  // Returns: A revision-guarded backup, or null when the store cannot suspend this account; storage errors propagate.
  Future<DoseScheduleBackup?> suspendSchedule() async {
    await initialize();
    final backup = await _store!.suspendDoseSchedules(owner);
    await reload();
    return backup;
  }

  // 변경이 서버에 적용되지 않았을 때 보관한 일정을 되돌린다. 그사이 다른 기록이 있었으면
  // 이전처럼 비운 상태로 둔다. 서버는 처방이 바뀐 뒤의 오프라인 기록을 거부하므로,
  // 응답만 잃은 변경이 실제로 적용됐어도 잘못된 기록은 남지 않는다.
  // Function Name: restoreSchedule
  // Description: Restores a suspended snapshot only if still safe; otherwise leaves schedules invalidated and reloads state.
  // Parameters: backup (DoseScheduleBackup?) - snapshot from suspendSchedule, possibly absent.
  // Returns: Completion after restoration/invalidation and reload; storage failures propagate.
  Future<void> restoreSchedule(DoseScheduleBackup? backup) async {
    await initialize();
    if (backup == null || !await _store!.restoreDoseSchedules(owner, backup)) {
      await _store!.invalidateDoseSchedules(owner);
    }
    await reload();
  }

  // Function Name: _refreshScheduleWindow
  // Description: Fetches courses with day/revision guards and requests another read after a revision collision.
  // Parameters: None; uses the injected loader and account store.
  // Returns: Completion without throwing on retrieval/storage failure; absent loaders and disposed sessions do nothing.
  Future<void> _refreshScheduleWindow() async {
    final loader = loadScheduleWindow;
    if (loader == null || _disposed) return;
    try {
      await initialize();
      final day = doseScheduleDay(clock());
      final revision = await _store!.cacheRevision(owner);
      final courses = await loader();
      if (_disposed || day != doseScheduleDay(clock())) return;
      final saved = await cacheScheduleWindow(
        courses,
        startDay: day,
        expectedRevision: revision,
      );
      // 받는 사이 저장 버전이 바뀌면(복용 전송 확인도 버전을 올린다) 낡았을 수 있는 기간을 버리고
      // 다시 받는다. 다시 받지 않으면 기간 일정 없이 남는다. 계정이 바뀌어 거부된 경우는 반복하지 않는다.
      if (!saved &&
          !_disposed &&
          await _store!.cacheRevision(owner) != revision) {
        _windowRefreshAgain = true;
      }
    } catch (_) {
      // 네트워크 실패는 이미 받은 기간을 늘리거나 기존 일정 조회를 실패로 바꾸지 않는다.
    }
  }

  // Function Name: cacheScheduleWindow
  // Description: Saves a bounded offline window only for today's live session and the expected store revision.
  // Parameters: courses (List<MedicationSchedule>) - server courses; startDay (String) - valid YYYY-MM-DD;
  // - expectedRevision (int): Cache version captured before loading.
  // Returns: False for stale day/session/revision; otherwise the store result. Invalid dates and storage errors propagate.
  Future<bool> cacheScheduleWindow(
    List<MedicationSchedule> courses, {
    required String startDay,
    required int expectedRevision,
  }) async {
    await initialize();
    if (_disposed || startDay != doseScheduleDay(clock())) return false;
    final start = DateTime.parse(startDay);
    return _store!.saveOfflineScheduleWindow(owner, {
      'start': startDay,
      'end': DateTime(
        start.year,
        start.month,
        start.day + OfflineScheduleWindow.maximumDays - 1,
      ).toIso8601String().substring(0, 10),
      'courses': courses.map((course) => course.toJson()).toList(),
    }, expectedRevision: expectedRevision);
  }

  // 함수이름: offlineWindow
  // 함수역할: 저장된 기간 일정이 오늘까지 유효하게 투영되는지 확인한다.
  // 매개변수: 없음.
  // 반환값: 유효한 원본 기간 데이터 또는 null. 초기화·읽기 오류는 전파한다.
  Future<Map<String, dynamic>?> offlineWindow() async {
    await initialize();
    final window = await _store!.readOfflineScheduleWindow(owner);
    return window != null &&
            OfflineScheduleWindow.project(window, doseScheduleDay(clock())) !=
                null
        ? window
        : null;
  }

  // 함수이름: resumeAfterAbortedSignOut
  // 함수역할: 취소된 로그아웃의 원래 세션임을 확인하며 저장소 세션과 재전송을 복구한다.
  // 매개변수: isCurrent (bool Function()) - 호출자의 세션이 아직 같은지 확인하는 함수
  // 반환값: 복구와 재조회 후에도 현재 세션이면 true. 계정 변경·종료·복구 거부는 false, 저장소 오류는 전파한다.
  Future<bool> resumeAfterAbortedSignOut(bool Function() isCurrent) async {
    await initialize();
    if (_disposed || !isCurrent()) return false;
    if (!await _store!.restoreDoseSession(
      owner,
      isCurrent: () => !_disposed && isCurrent(),
    )) {
      return false;
    }
    await reload();
    if (_disposed || !isCurrent()) return false;
    _scheduleRetry();
    return true;
  }

  // Function Name: cacheSchedules
  // Description: Cache a same-day read without relabeling it across async work.
  // Parameters: schedules - server snapshot; scheduleDate - day at request start;
  //   expectedRevision - optional guard against intervening sync receipts.
  // - awaitScheduleWindow (bool): Wait for the 14-day offline window that the store
  //   replaces with every same-day snapshot; a background worker must, because
  //   its process may end before an unawaited refresh finishes.
  // Returns: Completion, or StateError for an expired day; rejected revisions reload current state without replacing it.
  Future<void> cacheSchedules(
    List<MedicationSchedule> schedules, {
    required String scheduleDate,
    int? expectedRevision,
    bool awaitScheduleWindow = false,
  }) async {
    await initialize();
    if (scheduleDate != doseScheduleDay(clock())) {
      throw StateError('The medication schedule has expired. Please refresh.');
    }
    final cache = <String, dynamic>{
      'date': scheduleDate,
      'schedules': schedules.map((s) => s.toJson()).toList(),
    };
    final saved = await _store!.saveAuthoritativeDoseCache(
      owner,
      cache,
      expectedRevision: expectedRevision,
    );
    if (!saved) {
      await reload();
      return;
    }
    _confirmed = schedules;
    _cacheDate = scheduleDate;
    _operations = await _store!.pending(owner);
    // The next reload must not report this same snapshot as a new change.
    _fingerprint = _stateFingerprint(cache);
    await _publishState();
    final window = refreshScheduleWindow();
    if (awaitScheduleWindow) {
      await window;
    } else {
      unawaited(window);
    }
  }

  // 함수이름: _publishState
  // 함수역할: 표시 갱신 요청을 하나의 비동기 실행으로 합치며 종료된 세션에서는 무시한다.
  // 매개변수: 없음.
  // 반환값: 갱신 요청 접수 완료 Future. onStateChanged의 실제 완료는 기다리지 않는다.
  Future<void> _publishState() async {
    if (_disposed || onStateChanged == null) return;
    _publishAgain = true;
    if (_publishing) return;
    _publishing = true;
    unawaited(_publishLoop());
  }

  // 기기 저장 이후 표시 작업은 전송을 막지 않고 최신 변경을 합쳐 반영한다.
  // 함수이름: _publishLoop
  // 함수역할: 추가 요청이 있는 동안 표시 콜백을 순차 실행하고 실패해도 전송 기록은 유지한다.
  // 매개변수: 없음.
  // 반환값: 요청이 소진되거나 세션이 종료되면 완료. 콜백 예외는 삼키고 실행 중 표시를 해제한다.
  Future<void> _publishLoop() async {
    try {
      do {
        _publishAgain = false;
        try {
          await onStateChanged?.call();
        } catch (_) {
          // 위젯 표시 실패로 이미 저장한 복용 기록을 실패 처리하지 않는다.
        }
      } while (_publishAgain && !_disposed);
    } finally {
      _publishing = false;
    }
  }

  // Function Name: project
  // Description: Applies this service's queued changes for the current dose day to a supplied snapshot.
  // Parameters: schedules (List<MedicationSchedule>) - confirmed schedules to project.
  // Returns: New schedule copies with pending status overrides; source schedules are unchanged.
  List<MedicationSchedule> project(List<MedicationSchedule> schedules) =>
      projectDoseOperations(schedules, _operations, doseScheduleDay(clock()));

  // 함수이름: record
  // 함수역할: 사용자가 본 약 목록만 영속 저장한 뒤 전송을 예약한다.
  // 매개변수: medicationIds/slotKey/scheduleDate - 대상 일정,
  //           completed - 복용 여부, linkId - 선택적 채팅, medicationNames - 표시 이름.
  // 반환값: 큐에 저장했으면 true. 유효하지 않은 요청은 false, 저장 실패는 예외.
  Future<bool> record({
    required List<int> medicationIds,
    required String slotKey,
    required bool completed,
    String? scheduleDate,
    int? linkId,
    List<String> medicationNames = const [],
  }) async {
    await initialize();
    await reload();
    final today = doseScheduleDay(clock());
    if (_disposed ||
        medicationIds.isEmpty ||
        !medicationScheduleSlotKeys.contains(slotKey) ||
        (scheduleDate == null && _cacheDate != today)) {
      return false;
    }
    final id =
        'dose_${clock().microsecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
    final revisions = <String, int>{
      for (final schedule in _confirmed)
        if (medicationIds.contains(int.tryParse(schedule.medicationID)))
          schedule.medicationID: schedule.regimenRevision,
    };
    await _store!.enqueue(owner, {
      'operation_id': id,
      'schedule_date': scheduleDate ?? today,
      'slot_key': slotKey,
      'medication_ids': medicationIds.toSet().toList()..sort(),
      'completed': completed,
      'link_id': ?linkId,
      'medication_names': medicationNames,
      if (revisions.length == medicationIds.toSet().length)
        'regimen_revisions': revisions,
    });
    _operations = await _store!.pending(owner);
    if (!_disposed) notifyListeners();
    await _publishState();
    // OS 작업 예약이 실패해도 기록은 남아 다음 앱 실행이나 주기 작업에서 재전송한다.
    unawaited(scheduleWork().catchError((_) {}));
    unawaited(drain());
    _scheduleRetry();
    return true;
  }

  // 함수이름: drain
  // 함수역할: 동시 호출이 같은 전송 작업을 기다리도록 하며 완료 후 다음 전송을 허용한다.
  // 매개변수: 없음.
  // 반환값: 현재 큐 처리 완료 Future. 한 번에 전체 큐가 전송된다는 보장은 없다.
  Future<void> drain() =>
      _draining ??= _drain().whenComplete(() => _draining = null);

  // Function Name: _drain
  // Description: Leases at most 100 ordered operations, uploads and acknowledges them, and preserves retryable failures.
  // - Permanent HTTP failures block that dose chain; a daily chat limit removes only the chat side effect.
  // Parameters: None; uses the active owner, transport, clock, and store.
  // Returns: Completion after state reload and retry scheduling; caught upload failures leave records queued.
  Future<void> _drain() async {
    final acceptedBefore = _acceptedRevision;
    var reloaded = false;
    try {
      await initialize();
      for (var count = 0; count < 100 && !_disposed; count++) {
        if (!await _store!.isActive(owner)) return;
        final lease =
            '${clock().microsecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff)}';
        final op = await _store!.claim(
          owner,
          lease,
          clock().millisecondsSinceEpoch,
        );
        if (op == null) break;
        final id = op['operation_id'] as String;
        try {
          if (!await _store!.isActive(owner) || _disposed) {
            await _store!.finish(owner, id, lease, retry: true);
            return;
          }
          final response = await client
              .post(
                Uri.parse(
                  '${ApiConfig.baseUrl}/schedule/completion-operations',
                ).replace(queryParameters: {'patient_hash': owner}),
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode({...op}..remove('medication_names')),
              )
              .timeout(const Duration(seconds: 20));
          if (response.statusCode == 429 &&
              op['link_id'] != null &&
              _isChatDailyLimit(response)) {
            // 채팅 일일 한도는 채팅 복용 기록에만 먼저 적용된다. 연동이 끊긴 채팅 기록처럼
            // 채팅 없는 일반 복용 기록으로 바꿔 복용 상태가 한도 초기화까지 막히지 않게 한다.
            // 분당 한도 같은 다른 429는 잠시 뒤 다시 보내면 되므로 채팅 기록을 버리지 않는다.
            if (await _store!.replaceClaimed(
              owner,
              id,
              lease,
              withoutChatReceipt(op),
            )) {
              continue;
            }
            break;
          }
          if (response.statusCode != 200) {
            final permanent = const [
              400,
              403,
              404,
              409,
              422,
            ].contains(response.statusCode);
            await _store!.finish(
              owner,
              id,
              lease,
              blocked: permanent,
              retry: !permanent,
            );
            // 거부된 요청은 같은 날짜·시간대·약의 뒤 요청만 붙잡고, 관계없는 요청은 계속 보낸다.
            if (permanent) continue;
            break;
          }
          final body = jsonDecode(response.body) as Map;
          if (body['operation_id'] != id || body['data'] is! List) {
            throw const FormatException('Invalid sync receipt');
          }
          // 다음 취소 요청 전에 서버 상태 저장과 현재 요청 확인을 함께 마친다.
          await _store!.acknowledge(owner, id, lease, {
            'date': body['schedule_date'] ?? doseScheduleDay(clock()),
            'schedules': body['data'],
          });
          _acceptedRevision++;
          _retry = 0;
        } catch (_) {
          await _store!.finish(owner, id, lease, retry: true);
          break;
        }
      }
      await reload();
      reloaded = true;
    } catch (_) {
      // 저장소·인증·네트워크 오류가 나도 사용자의 전송 대기 기록을 버리지 않는다.
    } finally {
      // 서버가 받은 기록이 있는데 중간에 빠져나왔으면 기록 화면이 다시 읽도록 그 사실만 알린다.
      if (!reloaded && _acceptedRevision != acceptedBefore && !_disposed) {
        notifyListeners();
      }
      await _scheduleRetryIfUploadable();
    }
  }

  // Function Name: _scheduleRetryIfUploadable
  // Description: Clears retries/backoff when nothing is uploadable; storage inspection failures conservatively retain retries.
  // Parameters: None.
  // Returns: Completion after the retry decision; disposed sessions do nothing.
  Future<void> _scheduleRetryIfUploadable() async {
    if (_disposed) return;
    var uploadable = true;
    try {
      final store = _store;
      if (store != null) uploadable = await store.hasUploadableOperation(owner);
    } catch (_) {
      // 확인하지 못했으면 기록을 놓치지 않도록 재시도를 유지한다.
    }
    if (_disposed) return;
    if (!uploadable) {
      _timer?.cancel();
      _timer = null;
      _retry = 0;
      return;
    }
    _scheduleRetry();
  }

  // Function Name: flushPending
  // Description: Makes one best-effort upload attempt before session teardown without deleting unaccepted records.
  // Parameters: limit (Duration) - timeout applied separately to initialization, eligibility lookup, and draining.
  // Returns: Completion on success, timeout, or failure; timing out does not cancel an already-running upload.
  Future<void> flushPending({
    Duration limit = const Duration(seconds: 4),
  }) async {
    if (_disposed) return;
    try {
      await initialize().timeout(limit);
      // 서버가 거부해 보류된 기록만 남았으면 보낼 것이 없다.
      if (!await _store!.hasUploadableOperation(owner).timeout(limit)) return;
      await drain().timeout(limit);
    } catch (_) {
      // 오프라인이거나 응답이 늦으면 기다리지 않는다. 진행 중인 전송은 스스로 끝나거나 재시도로 남는다.
    }
  }

  // 함수이름: retryNow
  // 함수역할: 서버 거부로 보류된 기록을 다시 대기 상태로 바꾼 뒤 전송을 시도한다.
  // 매개변수: 없음.
  // 반환값: 재시도 처리 완료 Future. 초기화·보류 해제 오류는 전파한다.
  Future<void> retryNow() async {
    await initialize();
    await _store!.retryBlocked(owner);
    await drain();
  }

  // 함수이름: discardRejected
  // 함수역할: 지정한 보류 기록만 삭제하고 화면을 갱신한 뒤 나머지 기록을 전송한다.
  // 매개변수: id (String) - 사용자가 버리기로 선택한 operation_id
  // 반환값: 삭제·재조회·전송 시도 완료 Future. 저장소 오류는 전파한다.
  Future<void> discardRejected(String id) async {
    await initialize();
    await _store!.discardRejected(owner, id);
    await reload();
    await drain();
  }

  // Function Name: acknowledgeLostRecords
  // Description: Clears the account's loss notice after acknowledgement and reloads the presentation state.
  // Parameters: None.
  // Returns: Completion after persistence and reload; storage failures propagate.
  Future<void> acknowledgeLostRecords() async {
    await initialize();
    await _store!.clearLostOperations(owner);
    await reload();
  }

  // Function Name: deleteAccountData
  // Description: Deactivates the store, deletes this account's persisted data, and clears its in-memory dose state.
  // Parameters: None; callers coordinate session teardown before invoking this destructive account cleanup.
  // Returns: Completion after deletion; storage failures propagate and no listener notification is emitted here.
  Future<void> deleteAccountData() async {
    await initialize();
    await _store!.activate(null);
    await _store!.clearAccount(owner);
    _operations = const [];
    _lostRecordCount = 0;
    _confirmed = const [];
    _cacheDate = '';
  }

  // 함수이름: _scheduleRetry
  // 함수역할: 기존 타이머를 취소하고 활성 화면에서만 5·15·30·60·120초 간격으로 전송을 예약한다.
  // 매개변수: 없음.
  // 반환값: 없음. 최대 간격은 120초이며 종료·백그라운드 상태에서는 새 타이머를 만들지 않는다.
  void _scheduleRetry() {
    _timer?.cancel();
    if (_disposed || !_foreground) return;
    const delays = [5, 15, 30, 60, 120];
    final seconds = delays[min(_retry++, delays.length - 1)];
    _timer = Timer(Duration(seconds: seconds), () => unawaited(drain()));
  }

  // 함수이름: didChangeAppLifecycleState
  // 함수역할: 앱 상태가 바뀌면 대기 타이머를 취소하고 화면 복귀 시 즉시 전송을 요청한다.
  // 매개변수: state (AppLifecycleState) - Flutter가 전달한 새 상태
  // 반환값: 없음. 전송 완료를 기다리지 않는다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    if (_foreground) unawaited(drain());
  }

  // 함수이름: dispose
  // 함수역할: 후속 세션 작업을 막고 재시도 타이머·앱 상태 감시를 정리한다.
  // 매개변수: 없음.
  // 반환값: 없음. 호출자가 제공한 HTTP 연결과 공유 저장소는 닫지 않는다.
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

// Function Name: _isChatDailyLimit
// Description: Distinguishes the server's daily chat quota message from other HTTP 429 rate limits.
// Parameters: response (http.Response) - rejected dose-upload response, expected to be 429 by the caller.
// Returns: True for the recognized detail text; malformed UTF-8/JSON or another response body returns false.
bool _isChatDailyLimit(http.Response response) {
  try {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final detail = decoded is Map ? decoded['detail'] : null;
    return detail is String && detail.contains('오늘 보낼 수 있는 채팅 메시지');
  } catch (_) {
    return false;
  }
}
