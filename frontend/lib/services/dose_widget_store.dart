part of 'dose_outbox_store.dart';

// Widget actions and their outbox operation commit together. Multiple widgets,
// rapid taps and retried Android jobs cannot apply one button twice.
extension DoseWidgetStore on DoseOutboxStore {
  // 함수이름: updateWidget
  // 함수역할: 복용·취소 토큰과 직전 상태를 검증한 뒤 기록과 전송 대기를 함께 저장한다.
  // 매개변수: owner 계정, configuration 설정, action 동작, actionToken 중복 방지 토큰,
  //   now 날짜 검증 시각.
  // 반환값: 현재 계정의 위젯 상태. 로그아웃 또는 계정 불일치이면 null.
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
      final active = await tx.query(
        'metadata',
        where: 'name = ?',
        whereArgs: ['active'],
      );
      final token = active.firstOrNull?['value'] as String?;
      if (token == null ||
          token.isEmpty ||
          (expectedOwner != null && token != expectedOwner)) {
        return null;
      }
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
                : '${config['language'] == 'en' ? 'Patient' : '환자'} ${patient.substring(patient.length > 4 ? patient.length - 4 : 0).toUpperCase()}',
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

  // Resolve only current, active-account patient keys, never hashes from intents.
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
