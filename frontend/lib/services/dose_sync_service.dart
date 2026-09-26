// 파일명: dose_sync_service.dart
// 역할: 복용 변경을 기기에 먼저 저장하고 계정별 순서대로 서버에 재전송한다.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../entities/medication_schedule_entity.dart';
import 'api_config.dart';
import 'dose_outbox_store.dart';

// 함수이름: doseScheduleDay
// 함수역할: 표시 시간대와 별개로 서버와 같은 기준 날짜를 계산한다.
// 매개변수: now - 현재 시각. 반환값: 기본 UTC+09:00의 YYYY-MM-DD 날짜.
String doseScheduleDay(DateTime now) => now
    .toUtc()
    .add(
      const Duration(
        minutes: int.fromEnvironment(
          'APPLICATION_UTC_OFFSET_MINUTES',
          defaultValue: 540,
        ),
      ),
    )
    .toIso8601String()
    .substring(0, 10);

// 클래스명: DoseSyncService
// 역할: 계정별 전송 큐, 일정 캐시, 앱 수명주기에 따른 재시도를 관리한다.
// 속성: owner/client - 인증 범위와 통신, openStore - 암호화 저장소,
//       scheduleWork - 백그라운드 예약, onStateChanged - 위젯 등 표시 갱신.
class DoseSyncService extends ChangeNotifier with WidgetsBindingObserver {
  final String owner;
  final http.Client client;
  final Future<DoseOutboxStore> Function() openStore;
  final Future<void> Function() scheduleWork;
  final DateTime Function() clock;
  final Future<void> Function()? onStateChanged;
  DoseOutboxStore? _store;
  Future<void>? _initializing;
  Future<void>? _draining;
  Timer? _timer;
  bool _disposed = false;
  bool _foreground = true;
  bool _observing = false;
  int _retry = 0;
  List<Map<String, dynamic>> operations = const [];
  List<MedicationSchedule> _confirmed = const [];
  String _cacheDate = '';
  String _fingerprint = '';

  DoseSyncService({
    required this.owner,
    required this.client,
    Future<DoseOutboxStore> Function()? openStore,
    Future<void> Function()? scheduleWork,
    DateTime Function()? clock,
    this.onStateChanged,
  }) : openStore = openStore ?? DoseOutboxStore.open,
       scheduleWork = scheduleWork ?? (() async {}),
       clock = clock ?? DateTime.now;

  int get pendingCount => operations.length;
  bool get hasBlocked => operations.any((op) => op['state'] == 'blocked');
  bool get hasCache => _cacheDate == doseScheduleDay(clock());
  List<MedicationSchedule> get schedules =>
      project(hasCache ? _confirmed : const []);

  Future<void> initialize({bool activate = false}) =>
      _initializing ??= _initialize(activate);

  Future<void> _initialize(bool activate) async {
    _store = await openStore();
    if (activate) await _store!.activate(owner);
    await reload();
  }

  Future<void> start() async {
    await initialize(activate: true);
    if (_disposed) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(scheduleWork().catchError((_) {}));
    unawaited(drain());
    _scheduleRetry();
  }

  Future<void> reload() async {
    final cache = await _store!.readCache(owner);
    _cacheDate = cache?['date'] as String? ?? '';
    _confirmed = MedicationSchedule.fromScheduleJsonList(cache?['schedules']);
    operations = await _store!.pending(owner);
    final fingerprint = jsonEncode([
      doseScheduleDay(clock()),
      cache,
      operations,
    ]);
    if (fingerprint != _fingerprint) {
      _fingerprint = fingerprint;
      if (!_disposed) notifyListeners();
      await _publishState();
    }
  }

  Future<int> cacheRevision() async {
    await initialize();
    return _store!.cacheRevision(owner);
  }

  // Function Name: cacheSchedules
  // Description: Cache a same-day read without relabeling it across async work.
  // Parameters: schedules - server snapshot; scheduleDate - day at request start;
  //   expectedRevision - optional guard against intervening sync receipts.
  // Returns: Completion, or StateError if the snapshot has already expired.
  Future<void> cacheSchedules(
    List<MedicationSchedule> schedules, {
    required String scheduleDate,
    int? expectedRevision,
  }) async {
    await initialize();
    if (scheduleDate != doseScheduleDay(clock())) {
      throw StateError('The medication schedule has expired. Please refresh.');
    }
    final saved = await _store!.saveCache(owner, {
      'date': scheduleDate,
      'schedules': schedules.map((s) => s.toJson()).toList(),
    }, expectedRevision: expectedRevision);
    if (!saved) {
      await reload();
      return;
    }
    _confirmed = schedules;
    _cacheDate = scheduleDate;
    operations = await _store!.pending(owner);
    await _publishState();
  }

  Future<void> _publishState() async {
    if (_disposed) return;
    try {
      await onStateChanged?.call();
    } catch (_) {
      // 위젯 표시 실패로 이미 저장한 복용 기록을 실패 처리하지 않는다.
    }
  }

  List<MedicationSchedule> project(List<MedicationSchedule> schedules) {
    final today = doseScheduleDay(clock());
    return schedules.map((schedule) {
      final statuses = {
        for (final slot in schedule.slotKeys)
          slot: schedule.isSlotCompleted(slot),
      };
      for (final op in operations) {
        if (op['schedule_date'] == today &&
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
    final today = doseScheduleDay(clock());
    if (_disposed ||
        medicationIds.isEmpty ||
        !medicationScheduleSlotKeys.contains(slotKey) ||
        (scheduleDate == null && _cacheDate != today)) {
      return false;
    }
    final id =
        'dose_${clock().microsecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
    await _store!.enqueue(owner, {
      'operation_id': id,
      'schedule_date': scheduleDate ?? today,
      'slot_key': slotKey,
      'medication_ids': medicationIds.toSet().toList()..sort(),
      'completed': completed,
      'link_id': ?linkId,
      'medication_names': medicationNames,
    });
    operations = await _store!.pending(owner);
    if (!_disposed) notifyListeners();
    await _publishState();
    // OS 작업 예약이 실패해도 기록은 남아 다음 앱 실행이나 주기 작업에서 재전송한다.
    unawaited(scheduleWork().catchError((_) {}));
    unawaited(drain());
    _scheduleRetry();
    return true;
  }

  Future<void> drain() =>
      _draining ??= _drain().whenComplete(() => _draining = null);

  Future<void> _drain() async {
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
          _retry = 0;
        } catch (_) {
          await _store!.finish(owner, id, lease, retry: true);
          break;
        }
      }
      await reload();
    } catch (_) {
      // 저장소·인증·네트워크 오류가 나도 사용자의 전송 대기 기록을 버리지 않는다.
    } finally {
      _scheduleRetry();
    }
  }

  Future<void> retryNow() async {
    await initialize();
    await _store!.retryBlocked(owner);
    await drain();
  }

  Future<void> discardRejected(String id) async {
    await initialize();
    await _store!.discardRejected(owner, id);
    await reload();
    await drain();
  }

  Future<void> deleteAccountData() async {
    await initialize();
    await _store!.activate(null);
    await _store!.clearAccount(owner);
    operations = const [];
    _confirmed = const [];
    _cacheDate = '';
  }

  void _scheduleRetry() {
    _timer?.cancel();
    if (_disposed || !_foreground) return;
    const delays = [5, 15, 30, 60, 120];
    final seconds = delays[min(_retry++, delays.length - 1)];
    _timer = Timer(Duration(seconds: seconds), () => unawaited(drain()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    if (_foreground) unawaited(drain());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
