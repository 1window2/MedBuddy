// File Name: dose_widget_store.dart
// Role: Commits home-widget actions and their encrypted dose operations in one transaction.
part of 'dose_outbox_store.dart';

// Widget actions and their outbox operation commit together. Multiple widgets,
// rapid taps and retried Android jobs cannot apply one button twice.
// Class Name: DoseWidgetStore
// Role: Extends encrypted dose storage with account-guarded native widget state and actions.
// Responsibilities: Validate opaque action/navigation tokens, preserve caregiver read-only scope, and commit dose changes with widget state.
// Attributes: No additional fields; uses the enclosing outbox database, encryption, and ownership helpers.
extension DoseWidgetStore on DoseOutboxStore {
  // Function Name: updateWidget
  // Description: Atomically project and persist widget state for the active owner; accept only current-day, valid action tokens and matching patient-cache revisions.
  // Parameters: owner (String?): expected owner, otherwise stored owner; configuration (Map<String, dynamic>?): display settings; action/actionToken (String?): take/cancel intent and nonce; patientCache (Map<String, dynamic>?): current linked-patient data; expectedPatientRevision (String?): stale-cache guard; now (DateTime): projection day.
  // Returns: Future<DoseWidgetState?>: saved state, or null for missing/mismatched active ownership; storage/decryption errors propagate.
  Future<DoseWidgetState?> updateWidget({
    String? owner,
    Map<String, dynamic>? configuration,
    String? action,
    String? actionToken,
    Map<String, dynamic>? patientCache,
    String? expectedPatientRevision,
    required DateTime now,
  }) async {
    final expectedOwner = owner == null ? null : await ownerKey(owner);
    return db.transaction((tx) async {
      final token = await _activeToken(tx);
      if (token == null ||
          token.isEmpty ||
          (expectedOwner != null && token != expectedOwner)) {
        return null;
      }
      // 함수이름: read
      // 함수역할: 위젯 갱신 트랜잭션 안에서 활성 계정의 저장 상태를 복호화한다.
      // 매개변수: name (String) - 읽을 전체 메타데이터 키.
      // 반환값: 저장된 JSON 맵 또는 없으면 null. DB·복호화·형식 오류는 전파한다.
      Future<Map<String, dynamic>?> read(String name) async {
        final rows = await tx.query(
          'metadata',
          where: 'name = ?',
          whereArgs: [name],
        );
        return rows.isEmpty
            ? null
            : _decrypt(rows.single['value'] as String, token);
      }

      final previous = await read('widget:$token') ?? <String, dynamic>{};
      final account = owner ?? previous['owner'] as String?;
      if (account == null) return null;
      final config =
          configuration ??
          Map<String, dynamic>.from(previous['config'] as Map? ?? {});
      if ((previous['config'] as Map?)?['source'] != config['source']) {
        previous.remove('patient_cache');
        previous['patient_revision'] = newWidgetActionToken();
        previous.remove('take');
        previous.remove('takes');
        previous.remove('cancels');
      }
      previous['patient_revision'] ??= newWidgetActionToken();
      if (config['source'] == 'patients' &&
          patientCache != null &&
          patientCache['date'] == doseWidgetDay(now) &&
          (expectedPatientRevision == null ||
              previous['patient_revision'] == expectedPatientRevision)) {
        final oldCache = previous['patient_cache'] as Map?;
        final oldPatients =
            (oldCache?['date'] == patientCache['date']
                ? (oldCache?['patients'] as List?)
                : null) ??
            [];
        final patients = <Map<String, dynamic>>[];
        for (final entry
            in (patientCache['patients'] as List? ?? []).whereType<Map>()) {
          final link = entry['link'] as Map? ?? {};
          final id = link['link_id'];
          final patient = link['patient_hash']?.toString() ?? '';
          if (link['link_status'] != true ||
              link['caregiver_hash'] != account ||
              id is! int ||
              id <= 0 ||
              patient.isEmpty ||
              patient == account ||
              patients.any((p) => (p['link'] as Map)['link_id'] == id)) {
            continue;
          }
          final old = oldPatients
              .whereType<Map>()
              .where(
                (p) =>
                    (p['link'] as Map?)?['link_id'] == id &&
                    (p['link'] as Map?)?['patient_hash'] == patient,
              )
              .firstOrNull;
          final alias = link['patient_alias']?.toString().trim();
          patients.add({
            ...entry,
            'key': old?['key'] ?? newWidgetActionToken(),
            'alias': alias?.isNotEmpty == true
                ? alias
                : '${isEnglishLanguage(config['language']?.toString()) ? 'Patient' : '환자'} ${patient.substring(patient.length > 4 ? patient.length - 4 : 0).toUpperCase()}',
          });
        }
        previous['patient_cache'] = {...patientCache, 'patients': patients};
        previous['patient_revision'] = newWidgetActionToken();
      }
      final cache = await read('cache:$token');
      final rows = await tx.query(
        'operations',
        where: 'owner = ?',
        whereArgs: [token],
        orderBy: 'seq',
      );
      final operations = <Map<String, dynamic>>[
        for (final row in rows)
          {
            ...await _decrypt(row['payload'] as String, token),
            'state': row['state'],
          },
      ];
      final day = doseWidgetDay(now);
      // 화면을 넘겨 선택한 시간대도 해당 토큰에 연결된 약만 기록한다.
      final candidates = [
        if (action == 'take') ...[
          ...(previous['takes'] as Map? ?? {}).values.whereType<Map>(),
          if (previous['take'] is Map) previous['take'] as Map,
        ],
        if (action == 'cancel')
          ...(previous['cancels'] as Map? ?? {}).values.whereType<Map>(),
      ];
      final candidate = candidates
          .where((value) => value['token'] == actionToken)
          .firstOrNull;
      if ((action == 'take' || action == 'cancel') &&
          config['source'] != 'patients' &&
          candidate != null &&
          candidate['token'] == actionToken &&
          candidate['date'] == day &&
          cache?['date'] == day &&
          !operations.any((op) => op['state'] == 'blocked')) {
        final projected = DoseWidgetState.projectedSchedules(
          cache,
          operations,
          day,
        );
        final ids = (candidate['ids'] as List).cast<int>();
        final slot = candidate['slot'] as String;
        final completing = action == 'take';
        final valid =
            ids.isNotEmpty &&
            // 완료 화면을 본 뒤 약이 추가되었다면 오래된 취소 버튼을 적용하지 않는다.
            (completing ||
                projected
                    .where((s) => s.slotKeys.contains(slot))
                    .every(
                      (s) => ids.contains(int.tryParse(s.medicationID)),
                    )) &&
            ids.every(
              (id) => projected.any(
                (s) =>
                    int.tryParse(s.medicationID) == id &&
                    s.slotKeys.contains(slot) &&
                    s.isSlotCompleted(slot) != completing,
              ),
            );
        if (valid) {
          final operation = <String, dynamic>{
            'operation_id': actionToken,
            'schedule_date': day,
            'slot_key': slot,
            'medication_ids': ids,
            'completed': completing,
            'medication_names': candidate['names'],
            'regimen_revisions': {
              for (final schedule in projected)
                if (ids.contains(int.tryParse(schedule.medicationID)))
                  schedule.medicationID: schedule.regimenRevision,
            },
          };
          await tx.insert('operations', {
            'id': actionToken,
            'owner': token,
            'payload': await _encrypt(operation, token),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          operations.add({...operation, 'state': 'pending'});
          previous['take'] = null;
          (previous['takes'] as Map?)?.remove(slot);
          (previous['cancels'] as Map?)?.remove(slot);
        }
      }
      final result = DoseWidgetState.build(
        owner: account,
        cache: cache,
        operations: operations,
        previous: previous,
        now: now,
        configuration: config,
      );
      await tx.insert('metadata', {
        'name': 'widget:$token',
        'value': await _encrypt(result.data, token),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return result;
    });
  }

  // Function Name: widgetRefreshNeed
  // Description: Inspects display-source freshness without writing widget state or issuing new action tokens.
  // Parameters: now (DateTime) - clock used to determine the dose day.
  // Returns: Active owner and whether its selected self/patient snapshot is current; null without an active initialized widget.
  // - A failed patient snapshot is stale even on today's date; storage/decryption errors propagate.
  Future<({String owner, bool snapshotCurrent})?> widgetRefreshNeed({
    required DateTime now,
  }) async {
    // Function Name: read
    // Description: Decodes one account-scoped metadata value without mutating the stored projection.
    // Parameters: name (String) - complete metadata key; token (String) - owner hash for authenticated decryption.
    // Returns: Decoded map or null when absent; storage/decoding errors propagate.
    Future<Map<String, dynamic>?> read(String name, String token) async {
      final rows = await db.query(
        'metadata',
        where: 'name = ?',
        whereArgs: [name],
      );
      return rows.isEmpty
          ? null
          : _decrypt(rows.single['value'] as String, token);
    }

    final token = await _activeToken(db);
    if (token == null || token.isEmpty) return null;
    final widget = await read('widget:$token', token);
    final owner = widget?['owner'] as String?;
    if (owner == null) return null;
    final day = doseWidgetDay(now);
    if ((widget?['config'] as Map?)?['source'] == 'patients') {
      final cache = widget?['patient_cache'] as Map?;
      return (
        owner: owner,
        snapshotCurrent: cache?['date'] == day && cache?['failed'] != true,
      );
    }
    final cache = await read('cache:$token', token);
    return (owner: owner, snapshotCurrent: cache?['date'] == day);
  }

  // Resolve only current, active-account patient keys, never hashes from intents.
  // 함수이름: resolveWidgetPatient
  // 함수역할: 현재 계정의 위젯 상태를 다시 만들고 오늘의 환자 보기 탐색 토큰과 환자 키를 검증한다.
  // 매개변수: owner (String) - 활성 계정; patientKey/navigationKey (String) - 표시 상태의 불투명 키; now (DateTime) - 기준 시각.
  // 반환값: 일치한 저장 연동의 환자 해시 또는 null. 인텐트의 해시를 신뢰하지 않으며 저장소 오류는 전파한다.
  Future<String?> resolveWidgetPatient({
    required String owner,
    required String patientKey,
    required String navigationKey,
    required DateTime now,
  }) async {
    final state = await updateWidget(owner: owner, now: now);
    if (state?.view['source'] != 'patients' ||
        state?.view['navigation_key'] != navigationKey) {
      return null;
    }
    final cache = state?.data['patient_cache'] as Map?;
    if (cache?['date'] != doseWidgetDay(now)) return null;
    final entry = (cache?['patients'] as List? ?? [])
        .whereType<Map>()
        .where((p) => p['key'] == patientKey)
        .firstOrNull;
    return (entry?['link'] as Map?)?['patient_hash'] as String?;
  }
}
