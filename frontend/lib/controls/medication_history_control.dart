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
// 역할: 기록 화면을 연 세션이 바뀌어 더 이상 조회·저장할 수 없음을 나타낸다.
// 주요 책임: 이전 계정의 비동기 작업이 계속되지 않도록 호출자에게 중단을 알린다.
// 속성: 인스턴스 필드 없음; 민감한 계정 식별자를 포함하지 않는 표식 예외.
class MedicationHistorySessionChanged implements Exception {
  // 함수이름: MedicationHistorySessionChanged
  // 함수역할: 세션 변경을 민감한 식별자 없이 알리는 고정 예외를 만든다.
  // 매개변수: 없음.
  // 반환값: 상세 계정 정보를 담지 않는 예외.
  const MedicationHistorySessionChanged();
}

// 클래스명: MedicationHistoryBusy
// 역할: 이미 실행 중인 기록 조회·저장과 겹치는 요청을 구분한다.
// 주요 책임: 진행 중 작업을 덮지 않도록 중복 호출 거절을 전달한다.
// 속성: 인스턴스 필드 없는 표식 예외.
class MedicationHistoryBusy implements Exception {
  // 함수이름: MedicationHistoryBusy
  // 함수역할: 조회·저장의 중복 실행을 차단했음을 알리는 예외를 만든다.
  // 매개변수: 없음.
  // 반환값: 개인정보 없는 중복 작업 예외.
  const MedicationHistoryBusy();
}

// 세션·대상 환자를 고정하고 쓰기 완료가 확인되기 전에는 화면에 성공 상태를 만들지 않는다.
// Class Name: MedicationHistoryControl
// Role: Coordinates session-bound patient history, corrections, and durable as-needed intents.
// Responsibilities: Reject stale sessions/read-only writes; validate date ranges and server acknowledgements before publishing success.
// Attributes: patientHash/readOnly: Scope; _client/_pendingStore/_now: Dependencies; snapshot/error/loading/saving/savedRevision: Presentation state; _sessionKey/_invalidated: Identity guards.
class MedicationHistoryControl extends ChangeNotifier {
  // 함수이름: MedicationHistoryControl
  // 함수역할: 환자 범위를 검사하고 인증 통신·시계·필요시 대기 저장소와 세션 변경 구독을 구성한다.
  // 매개변수: patientHash: 비어 있지 않은 환자; readOnly: 쓰기 제한; baseUrl/client: API·외부 소유 전송기; now/sessionKeyProvider/sessionChanges: 시계·신원 공급자; requestTimeout: 요청 제한; pendingStore: 대기 저장소.
  // 반환값: 컨트롤 인스턴스. 빈 환자는 ArgumentError이며 자체 생성한 전송기만 dispose에서 닫는다.
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
  // 서버가 정정을 확인할 때마다 하나씩 늘어난다. 같은 환자의 다른 기록 화면이 다시 읽는 신호로 쓴다.
  int savedRevision = 0;
  // 일정 화면을 닫아도 같은 로그인 세션에서는 미확인 필요시 복용 의도를 재사용한다.
  final List<MedicationHistoryChange> pendingAsNeededChanges = [];
  // 함수이름: pendingAsNeededChange
  // 함수역할: 호환용 단일 접근자로 첫 미확인 필요시 복용 요청을 읽는다.
  // 매개변수: 없음.
  // 반환값: 첫 변경 또는 대기 목록이 비어 있으면 null.
  MedicationHistoryChange? get pendingAsNeededChange =>
      pendingAsNeededChanges.firstOrNull;
  // 함수이름: pendingAsNeededChange
  // 함수역할: 메모리의 미확인 필요시 복용 목록을 단일 요청 또는 빈 목록으로 대체한다.
  // 매개변수: change (MedicationHistoryChange?): 유지할 한 요청, null이면 모두 비움.
  // 반환값: 없음. 디스크 저장이나 리스너 통지는 하지 않는다.
  set pendingAsNeededChange(MedicationHistoryChange? change) {
    pendingAsNeededChanges
      ..clear()
      ..addAll(change == null ? [] : [change]);
  }

  MedicationHistoryRange? requestedRange;

  // 함수이름: restorePendingAsNeeded
  // 함수역할: 동일 세션의 암호화 대기 요청을 한 번 복원하고 요청 ID가 겹치지 않게 합친다.
  // 매개변수: 없음.
  // 반환값: 완료 Future. 읽기 전용·이미 복원한 경우 생략하며 실패는 화면 오류에 반영하고 전파한다.
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

  // 함수이름: stageAsNeededChanges
  // 함수역할: 신규 필요시 복용 요청을 검증·영속화하고 저장소가 유지한 요청 목록으로 메모리를 갱신한다.
  // 매개변수: changes (List<MedicationHistoryChange>): 버전 0인 신규 필요시 변경들.
  // 반환값: 완료 Future. 읽기 전용·잘못된 변경·세션 변경·저장 오류는 전파한다.
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

  // 함수이름: removePendingAsNeeded
  // 함수역할: 확인한 요청 ID만 디스크와 메모리의 대기 목록에서 제거한다.
  // 매개변수: operationIds (Set<String>): 제거할 요청 ID.
  // 반환값: 완료 Future. 빈 집합은 무시하며 세션·저장소 오류는 전파한다.
  Future<void> removePendingAsNeeded(Set<String> operationIds) async {
    if (operationIds.isEmpty) return;
    ensureSession();
    await _pendingStore.remove(patientHash, operationIds);
    ensureSession();
    pendingAsNeededChanges.removeWhere(
      (change) => operationIds.contains(change.operationId),
    );
  }

  // 함수이름: busy
  // 함수역할: 중복 명령 방지에 사용할 조회·저장 진행 상태를 합친다.
  // 매개변수: 없음.
  // 반환값: loading 또는 saving이면 true.
  bool get busy => loading || saving;
  // 함수이름: sessionInvalidated
  // 함수역할: 기존 화면이 더 이상 재사용할 수 없는 세션인지 확인한다.
  // 매개변수: 없음.
  // 반환값: 한 번 무효화된 경우 true; 재로그인해도 이 인스턴스는 복구하지 않는다.
  bool get sessionInvalidated => _invalidated;
  // 함수이름: now
  // 함수역할: 날짜 검증에 쓸 주입된 현재 시각을 읽는다.
  // 매개변수: 없음.
  // 반환값: _now가 반환한 DateTime.
  DateTime get now => _now();
  // 함수이름: today
  // 함수역할: 현재 실제 시각을 복약 기록의 한국 날짜로 변환한다.
  // 매개변수: 없음.
  // 반환값: 시간 성분을 제거한 기준일 DateTime.
  DateTime get today => MedicationHistoryDates.today(now);

  // 함수이름: newOperationId
  // 함수역할: 재시도에 유지할 사용자 의도 식별자를 암호학적 난수로 생성한다.
  // 매개변수: 없음.
  // 반환값: 소문자 버전 4 UUID 문자열; 난수 공급 오류는 전파한다.
  static String newOperationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  // 함수이름: ensureSession
  // 함수역할: 생성 당시 신원과 현재 신원이 같은지 확인하고 종료·변경 상태를 거부한다.
  // 매개변수: 없음.
  // 반환값: 없음. 무효 세션은 자료를 지운 뒤 MedicationHistorySessionChanged를 던진다.
  void ensureSession() {
    if (_disposed ||
        _invalidated ||
        _sessionKey == null ||
        _sessionKeyProvider() != _sessionKey) {
      invalidateSession();
      throw const MedicationHistorySessionChanged();
    }
  }

  // 함수이름: invalidateSession
  // 함수역할: 이전 환자 스냅샷과 메모리 대기 요청을 지우고 세션 만료를 화면에 알린다.
  // 매개변수: 없음.
  // 반환값: 없음. 종료되었거나 이미 무효화된 경우 아무 작업도 하지 않는다.
  void invalidateSession() {
    if (_disposed || _invalidated) return;
    _invalidated = true;
    snapshot = null;
    pendingAsNeededChange = null;
    error = const MedicationHistorySessionChanged();
    notifyListeners();
  }

  // Function Name: load
  // Description: Loads a period with exclusive busy state, optionally retaining the same period only while revalidating it.
  // Parameters: range (MedicationHistoryRange): Requested period; preserveSnapshot (bool): Keep matching data during refresh.
  // Returns: Completion after publishing a validated snapshot; session/read failures discard the snapshot and propagate.
  Future<void> load(
    MedicationHistoryRange range, {
    bool preserveSnapshot = false,
  }) async {
    ensureSession();
    if (busy) throw const MedicationHistoryBusy();
    requestedRange = range;
    if (!preserveSnapshot ||
        snapshot?.range.start != range.start ||
        snapshot?.range.end != range.end) {
      snapshot = null;
    }
    error = null;
    loading = true;
    notifyListeners();
    try {
      snapshot = await _readPeriod(range);
    } catch (failure) {
      snapshot = null;
      if (!_disposed && !_invalidated) error = failure;
      rethrow;
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  // Function Name: _readPeriod
  // Description: Reads up to the export limit in newest-first API-sized chunks and publishes only a fully assembled result.
  // Parameters: range (MedicationHistoryRange): Valid period up to maximumExportDays.
  // Returns: Merged snapshot with medications deduplicated by ID; validation, session, or chunk failures propagate.
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

  // Function Name: readRangeForExport
  // Description: Loads an export period while preserving the currently displayed history snapshot.
  // Parameters: range (MedicationHistoryRange): Requested share/export period.
  // Returns: Independent snapshot Future; concurrent work is rejected and errors are exposed only when no display snapshot exists.
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

  // 함수이름: _readRange
  // 함수역할: 환자·기간 쿼리로 이력을 요청하고 응답의 성공 상태와 기간 일치를 검사한다.
  // 매개변수: range (MedicationHistoryRange): 단일 API 조회 한도 안의 기간.
  // 반환값: 검증된 스냅샷 Future. 기간·세션·HTTP·파싱·응답 불일치 오류는 전파한다.
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

  // Function Name: save
  // Description: Validates and submits one correction, durably staging new as-needed intents and clearing them only after server acknowledgement.
  // Parameters: change (MedicationHistoryChange): Revision/UUID-bearing correction.
  // Returns: Completion after confirmed success and savedRevision increment; read-only/busy/session/validation/transport failures throw and unacknowledged intents remain.
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
      savedRevision++;
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  // 함수이름: _requireSuccess
  // 함수역할: HTTP 200만 성공으로 인정하고 실패 응답을 상태 코드가 보존되는 오류로 변환한다.
  // 매개변수: response (http.Response): 서버 응답; operation (String): 진단용 작업명.
  // 반환값: 없음. 401·403에서는 스냅샷을 비운 뒤 HTTP 오류를 던진다.
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

  // 함수이름: dispose
  // 함수역할: 늦은 결과 반영을 막고 세션 구독·자체 소유 전송기·리스너를 정리한다.
  // 매개변수: 없음.
  // 반환값: 없음. 주입한 전송기는 닫지 않으며 디스크 대기 요청은 유지한다.
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
