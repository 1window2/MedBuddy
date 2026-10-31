// 파일명: medication_history_control.dart
// 역할: 인증된 환자 범위에서 복약 이력을 조회·정정하고 이전 세션의 결과를 폐기한다.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../entities/medication_history_entity.dart';
import '../entities/calendar_days.dart';
import '../services/api_config.dart';
import '../services/api_response_parser.dart';
import '../services/auth_config.dart';
import '../services/authenticated_api_client.dart';
import '../services/as_needed_pending_store.dart';

// 클래스명: MedicationHistorySessionChanged
// 역할: 화면을 연 세션이 바뀌어 더 이상 자료를 읽거나 저장할 수 없음을 나타낸다.
class MedicationHistorySessionChanged implements Exception {
  // 함수역할: 민감한 세션 식별자를 포함하지 않는 고정 오류를 만든다.
  const MedicationHistorySessionChanged();
}

// 클래스명: MedicationHistoryBusy
// 역할: 이미 실행 중인 조회·저장과 겹치는 작업을 구분한다.
class MedicationHistoryBusy implements Exception {
  // 함수역할: 중복 작업 차단 결과를 개인정보 없는 오류로 만든다.
  const MedicationHistoryBusy();
}

// 세션·대상 환자를 고정하고 쓰기 완료가 확인되기 전에는 화면에 성공 상태를 만들지 않는다.
// 클래스명: MedicationHistoryControl
// 역할: 환자 범위·읽기 전용 권한·네트워크 수명과 날짜별 복약 보고를 관리한다.
class MedicationHistoryControl extends ChangeNotifier {
  // 함수역할: 환자·권한·전송기·시계를 연결하며 빈 환자 범위는 거부하고 세션 변경을 감시한다.
  // 매개변수: client를 주입하면 호출자가 소유한다. 반환값: 화면 수명에 맞춰 정리할 제어 객체.
  MedicationHistoryControl({
    required String patientHash,
    this.readOnly = false,
    this.baseUrl = ApiConfig.baseUrl,
    http.Client? client,
    DateTime Function()? now,
    String? Function()? sessionKeyProvider,
    Stream<String?>? sessionChanges,
    this.requestTimeout = const Duration(seconds: 25),
    AsNeededPendingStore? pendingStore,
  }) : patientHash = patientHash.trim(),
       _ownsClient = client == null,
       _pendingStore = pendingStore ?? AsNeededPendingStore(),
       _now = now ?? DateTime.now {
    if (this.patientHash.isEmpty) {
      throw ArgumentError.value(
        patientHash,
        'patientHash',
        'A patient scope is required.',
      );
    }
    _sessionKeyProvider =
        sessionKeyProvider ??
        (() => AuthConfig.mode == AuthenticationMode.firebase
            ? FirebaseAuth.instance.currentUser?.uid
            : this.patientHash);
    _sessionKey = _sessionKeyProvider();
    _client =
        client ??
        AuthenticatedApiClient(
          tokenProvider: () async {
            ensureSession();
            if (AuthConfig.mode == AuthenticationMode.disabled) return null;
            final token = await FirebaseAuth.instance.currentUser?.getIdToken();
            ensureSession();
            return token;
          },
        );
    final changes =
        sessionChanges ??
        (sessionKeyProvider == null &&
                AuthConfig.mode == AuthenticationMode.firebase
            ? FirebaseAuth.instance.authStateChanges().map((user) => user?.uid)
            : null);
    _sessionSubscription = changes?.listen((key) {
      if (key != _sessionKey) invalidateSession();
    });
  }

  final String patientHash;
  final bool readOnly;
  final String baseUrl;
  final Duration requestTimeout;
  late final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final AsNeededPendingStore _pendingStore;
  bool _pendingRestored = false;
  late final String? Function() _sessionKeyProvider;
  late final String? _sessionKey;
  StreamSubscription<String?>? _sessionSubscription;
  bool _disposed = false;
  bool _invalidated = false;
  bool loading = false;
  bool saving = false;
  Object? error;
  MedicationHistorySnapshot? snapshot;
  // 일정 화면을 닫아도 같은 로그인 세션에서는 미확인 필요시 복용 의도를 재사용한다.
  final List<MedicationHistoryChange> pendingAsNeededChanges = [];
  MedicationHistoryChange? get pendingAsNeededChange =>
      pendingAsNeededChanges.firstOrNull;
  set pendingAsNeededChange(MedicationHistoryChange? change) {
    pendingAsNeededChanges
      ..clear()
      ..addAll(change == null ? [] : [change]);
  }

  MedicationHistoryRange? requestedRange;

  // 재시작 뒤에도 새 요청을 만들기 전에 같은 계정의 미확인 의도를 먼저 복원한다.
  Future<void> restorePendingAsNeeded() async {
    ensureSession();
    if (readOnly || _pendingRestored) return;
    try {
      final changes = await _pendingStore.read(patientHash);
      ensureSession();
      final existing = pendingAsNeededChanges
          .map((change) => change.operationId)
          .toSet();
      pendingAsNeededChanges.addAll(
        changes.where((change) => !existing.contains(change.operationId)),
      );
      _pendingRestored = true;
    } catch (failure) {
      if (!_disposed && !_invalidated) {
        error = failure;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> stageAsNeededChanges(
    List<MedicationHistoryChange> changes,
  ) async {
    ensureSession();
    if (readOnly) throw StateError('Caregiver history is read-only.');
    for (final change in changes) {
      change.validate(now);
      if (!change.entry.isAsNeeded || change.entry.revision != 0) {
        throw const FormatException('Only new as-needed doses can be staged.');
      }
    }
    final staged = await _pendingStore.stage(patientHash, changes);
    ensureSession();
    pendingAsNeededChanges
      ..clear()
      ..addAll(staged);
    _pendingRestored = true;
  }

  Future<void> removePendingAsNeeded(Set<String> operationIds) async {
    if (operationIds.isEmpty) return;
    ensureSession();
    await _pendingStore.remove(patientHash, operationIds);
    ensureSession();
    pendingAsNeededChanges.removeWhere(
      (change) => operationIds.contains(change.operationId),
    );
  }

  // 함수역할: 조회 또는 저장 중인지 알려 UI의 중복 명령을 막는다.
  bool get busy => loading || saving;
  // 함수역할: 한 번 무효화한 세션인지 반환하며 재로그인해도 기존 화면을 재사용하지 않는다.
  bool get sessionInvalidated => _invalidated;
  // 함수역할: 주입된 시계의 실제 현재 시각을 반환한다.
  DateTime get now => _now();
  // 함수역할: 현재 실제 시각에 해당하는 한국 날짜를 반환한다.
  DateTime get today => MedicationHistoryDates.today(now);

  // 함수역할: 새 사용자 의도 또는 필요시 이벤트를 식별하는 무작위 버전 4 UUID를 만든다.
  static String newOperationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  // 함수역할: 처음 세션과 현재 신원이 같은지 확인하고 다르면 자료를 지운 뒤 예외를 던진다.
  void ensureSession() {
    if (_disposed ||
        _invalidated ||
        _sessionKey == null ||
        _sessionKeyProvider() != _sessionKey) {
      invalidateSession();
      throw const MedicationHistorySessionChanged();
    }
  }

  // 함수역할: 이전 환자 자료를 즉시 지우고 열려 있는 화면·대화상자에 무효화를 알린다.
  void invalidateSession() {
    if (_disposed || _invalidated) return;
    _invalidated = true;
    snapshot = null;
    pendingAsNeededChange = null;
    error = const MedicationHistorySessionChanged();
    notifyListeners();
  }

  // 함수역할: 범위를 검증한 후 인증된 GET으로 이력을 새로 읽는다. 실패한 조회에는 이전 자료를 남기지 않는다.
  Future<void> load(MedicationHistoryRange range) async {
    ensureSession();
    if (busy) throw const MedicationHistoryBusy();
    requestedRange = range;
    snapshot = null;
    error = null;
    loading = true;
    notifyListeners();
    try {
      snapshot = await _readPeriod(range);
    } catch (failure) {
      if (!_disposed && !_invalidated) error = failure;
      rethrow;
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  // 서버는 한 번에 31일만 주므로 최대 90일을 최신 구간부터 나눠 읽고, 모든 구간이 성공해야 결과를 공개한다.
  Future<MedicationHistorySnapshot> _readPeriod(
    MedicationHistoryRange range,
  ) async {
    range.validate(now, maxDays: MedicationHistoryRange.maximumExportDays);
    if (range.days <= MedicationHistoryRange.maximumReadDays) {
      return _readRange(range);
    }
    final items = <MedicationHistoryEntry>[];
    final medications = <int, MedicationHistoryMedication>{};
    var end = range.end;
    while (!end.isBefore(range.start)) {
      ensureSession();
      final chunkStart = addCalendarDays(
        end,
        1 - MedicationHistoryRange.maximumReadDays,
      );
      final chunk = await _readRange(
        MedicationHistoryRange(
          chunkStart.isBefore(range.start) ? range.start : chunkStart,
          end,
        ),
      );
      // 구간마다 최신 날짜부터 정렬돼 있으므로 최신 구간부터 이어 붙이면 전체 순서가 유지된다.
      items.addAll(chunk.items);
      for (final medication in chunk.medications) {
        medications.putIfAbsent(medication.id, () => medication);
      }
      end = addCalendarDays(chunkStart, -1);
    }
    return MedicationHistorySnapshot(
      range: range,
      items: items,
      medications: medications.values.toList(),
    );
  }

  // 날짜별 화면은 그대로 두고 공유할 기간만 별도로 읽는다.
  Future<MedicationHistorySnapshot> readRangeForExport(
    MedicationHistoryRange range,
  ) async {
    ensureSession();
    if (busy) throw const MedicationHistoryBusy();
    loading = true;
    notifyListeners();
    try {
      return await _readPeriod(range);
    } catch (failure) {
      if (!_disposed && !_invalidated && snapshot == null) error = failure;
      rethrow;
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  // 화면 조회와 내보내기에 같은 기간 검증·세션 확인을 적용한다.
  Future<MedicationHistorySnapshot> _readRange(
    MedicationHistoryRange range,
  ) async {
    range.validate(now);
    final uri = Uri.parse('$baseUrl/care/history').replace(
      queryParameters: {
        'patient_hash': patientHash,
        'start_date': MedicationHistoryDates.format(range.start),
        'end_date': MedicationHistoryDates.format(range.end),
      },
    );
    final response = await _client.get(uri).timeout(requestTimeout);
    ensureSession();
    _requireSuccess(response, 'Medication history lookup failed');
    final body = ApiResponseParser.decodeMap(
      ApiResponseParser.decodeBody(response),
    );
    if (body['success'] == false) {
      throw const FormatException('History lookup was rejected.');
    }
    final result = MedicationHistorySnapshot.fromJson(body);
    if (result.range.start != range.start || result.range.end != range.end) {
      throw const FormatException('History response has a different period.');
    }
    return result;
  }

  // 함수역할: 읽기 전용·중복 작업·미래 시각을 거부하고 버전과 UUID를 포함한 PUT 확인만 성공으로 인정한다.
  Future<void> save(MedicationHistoryChange change) async {
    ensureSession();
    if (readOnly) throw StateError('Caregiver history is read-only.');
    if (busy) throw const MedicationHistoryBusy();
    change.validate(now);
    saving = true;
    notifyListeners();
    try {
      final entry = change.entry;
      final isNewAsNeeded = entry.isAsNeeded && entry.revision == 0;
      if (isNewAsNeeded) {
        await stageAsNeededChanges([change]);
        if (!pendingAsNeededChanges.any(
          (pending) => pending.operationId == change.operationId,
        )) {
          throw const MedicationHistoryBusy();
        }
      }
      final uri = Uri.parse(baseUrl).replace(
        pathSegments: [
          ...Uri.parse(baseUrl).pathSegments,
          'care',
          'history',
          '${entry.medicationId}',
          MedicationHistoryDates.format(entry.scheduleDate),
          entry.slotKey,
        ],
      );
      final response = await _client
          .put(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(change.toJson(patientHash)),
          )
          .timeout(requestTimeout);
      ensureSession();
      _requireSuccess(response, 'Medication history correction failed');
      final body = ApiResponseParser.decodeMap(
        ApiResponseParser.decodeBody(response),
      );
      if (body['success'] != true) {
        throw const FormatException('History correction was not acknowledged.');
      }
      if (isNewAsNeeded) await removePendingAsNeeded({change.operationId});
      // 갱신 전 데이터는 내보내기에 사용하지 않고 서버에서 다시 읽는다.
      snapshot = null;
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  // 함수역할: 성공 코드가 아닌 HTTP 응답을 상태 코드가 보존되는 오류로 전달한다.
  void _requireSuccess(http.Response response, String operation) {
    if (response.statusCode != 200) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        snapshot = null;
      }
      throw ApiResponseParser.httpFailure(
        operation,
        response,
        ApiResponseParser.decodeBody(response),
      );
    }
  }

  // 함수역할: 세션 구독과 직접 소유한 전송기를 종료하고 늦게 도착한 결과의 반영을 차단한다.
  @override
  void dispose() {
    _disposed = true;
    snapshot = null;
    pendingAsNeededChange = null;
    unawaited(_sessionSubscription?.cancel());
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
