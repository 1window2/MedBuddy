// 파일명: check_prescription_change_control_test.dart
// 역할: 처방 변화 Control의 요청 범위와 응답 변환을 검증한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/check_prescription_change_control.dart';
import 'package:medbuddy_frontend/entities/analyzed_medication_entity.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_schedule_entity.dart';
import 'package:medbuddy_frontend/entities/prescription_change_entity.dart';

void main() {
  test(
    'requestPrescriptionChange sends patient-scoped schedule payload',
    () async {
      final client = MockClient((http.Request request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/prescription/change-radar');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['patient_hash'], 'patient-a');
        expect(payload['prescription_date'], '2026-07-15');
        final medications = payload['medications'] as List<dynamic>;
        expect(medications, hasLength(1));
        expect(medications.first['item_seq'], 'ITEM-1');
        expect(medications.first['efficacy'], '효능');
        expect(medications.first['dosage_per_time'], '1정');
        expect(medications.first['daily_frequency'], '1일 3회');
        expect(medications.first['total_days'], '7일');

        return http.Response(
          jsonEncode({
            'has_previous_prescription': true,
            'comparison_status': 'comparable',
            'comparison_window_days': 90,
            'similarity_score': 1.0,
            'match_basis': 'same_medication',
            'previous_prescription_date': '2026-07-01',
            'current_prescription_date': '2026-07-15',
            'summary': {
              'added_count': 0,
              'missing_count': 0,
              'schedule_changed_count': 1,
              'unchanged_count': 0,
            },
            'changes': [
              {
                'change_type': 'schedule_changed',
                'item_name': '테스트정',
                'changed_fields': ['daily_frequency'],
                'previous': {
                  'dosage_per_time': '1정',
                  'daily_frequency': '1일 2회',
                  'total_days': '7일',
                },
                'current': {
                  'dosage_per_time': '1정',
                  'daily_frequency': '1일 3회',
                  'total_days': '7일',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final control = CheckPrescriptionChange(
        baseUrl: 'http://localhost',
        patientHash: 'patient-a',
        client: client,
      );

      final radar = await control.requestPrescriptionChange([
        AnalyzedMedication(
          schedule: MedicationSchedule(
            medicationName: '테스트정',
            prescriptionDate: DateTime(2026, 7, 15),
            dosage: '1정',
            intakeTime: '1일 3회',
            medicationTime: 7,
          ),
          detail: const MedicationDetail(
            itemSeq: 'ITEM-1',
            itemName: '테스트정',
            efficacy: '효능',
            usageMethod: '복용법',
            warning: '주의사항',
          ),
        ),
      ]);

      expect(radar.hasPreviousPrescription, isTrue);
      expect(radar.comparisonStatus, PrescriptionComparisonStatus.comparable);
      expect(radar.comparisonWindowDays, 90);
      expect(radar.matchBasis, 'same_medication');
      expect(radar.summary.scheduleChangedCount, 1);
      expect(radar.changes.single.type, PrescriptionChangeType.scheduleChanged);
      expect(radar.changes.single.changedFields, ['daily_frequency']);
    },
  );
}
