import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/services/caregiver_patient_local_state_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('환자 별칭이 없으면 짧은 기본 식별명을 사용한다', () async {
    final preferences = await SharedPreferences.getInstance();

    final label = CaregiverPatientLocalStateService.resolveLabel(
      preferences,
      caregiverHash: 'caregiver_test',
      patientHash: 'patient_alpha',
    );

    expect(label, '환자 LPHA');
    expect(CaregiverPatientLocalStateService.fallbackLabel(''), '연결된 환자');
  });

  test('같은 보호자의 환자별 별칭을 독립적으로 저장한다', () async {
    final preferences = await SharedPreferences.getInstance();

    await CaregiverPatientLocalStateService.saveLabel(
      preferences,
      caregiverHash: 'caregiver_test',
      patientHash: 'patient_a',
      label: '어머니',
    );
    await CaregiverPatientLocalStateService.saveLabel(
      preferences,
      caregiverHash: 'caregiver_test',
      patientHash: 'patient_b',
      label: '아버지',
    );

    expect(
      CaregiverPatientLocalStateService.resolveLabel(
        preferences,
        caregiverHash: 'caregiver_test',
        patientHash: 'patient_a',
      ),
      '어머니',
    );
    expect(
      CaregiverPatientLocalStateService.resolveLabel(
        preferences,
        caregiverHash: 'caregiver_test',
        patientHash: 'patient_b',
      ),
      '아버지',
    );
  });

  test('연결 해제된 환자의 별칭과 알림 캐시만 제거한다', () async {
    SharedPreferences.setMockInitialValues({
      'caregiver_linked_patients.caregiver_test': ['patient_a', 'patient_b'],
      'caregiver_patient_label.caregiver_test.patient_a': '어머니',
      'caregiver_patient_label.caregiver_test.patient_b': '아버지',
      'caregiver_alert.caregiver_test.patient_a.morning.mode': 'dose_completed',
      'caregiver_alert.caregiver_test.patient_b.morning.mode': 'dose_completed',
    });
    final preferences = await SharedPreferences.getInstance();

    await CaregiverPatientLocalStateService.synchronizeLinkedPatients(
      preferences,
      caregiverHash: 'caregiver_test',
      patientHashes: const ['patient_b'],
    );

    expect(
      preferences.getString('caregiver_patient_label.caregiver_test.patient_a'),
      isNull,
    );
    expect(
      preferences.getString(
        'caregiver_alert.caregiver_test.patient_a.morning.mode',
      ),
      isNull,
    );
    expect(
      preferences.getString('caregiver_patient_label.caregiver_test.patient_b'),
      '아버지',
    );
  });
}
