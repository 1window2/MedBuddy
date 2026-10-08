// 파일명: caregiver_patient_local_state_service_test.dart
// 역할: 보호자별 환자 별칭과 알림 캐시 정리을 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:medbuddy_frontend/controls/manage_caregiver_patient_local_state_control.dart';
import 'package:medbuddy_frontend/entities/patient_caregiver_link_entity.dart';
import 'package:medbuddy_frontend/services/caregiver_patient_local_state_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 클래스명: _RecordingPreferences
// 역할: 별칭 저장이 저장소에 실제로 쓴 횟수를 확인하기 위한 메모리 저장소 대역.
// 주요 책임:
// - 문자열 값의 조회·저장·삭제만 메모리 맵으로 처리하고 쓰기와 삭제 호출을 기록한다.
// 속성:
// - values (Map<String, String>): 현재 저장된 문자열 값.
// - writtenKeys (List<String>): setString으로 쓴 키의 호출 순서.
// - removedKeys (List<String>): remove로 지운 키의 호출 순서.
class _RecordingPreferences implements SharedPreferences {
  final Map<String, String> values = {};
  final List<String> writtenKeys = [];
  final List<String> removedKeys = [];

  // 함수이름: getString
  // 함수역할: 메모리 맵에서 문자열 값을 읽는다.
  // 매개변수: key (String): 조회할 저장 키. 반환값: 저장된 값 또는 null.
  @override
  String? getString(String key) => values[key];

  // 함수이름: containsKey
  // 함수역할: 메모리 맵에 키가 있는지 확인한다.
  // 매개변수: key (String): 확인할 저장 키. 반환값: 값이 있으면 true.
  @override
  bool containsKey(String key) => values.containsKey(key);

  // 함수이름: setString
  // 함수역할: 쓰기 호출을 기록하고 값을 메모리 맵에 저장한다.
  // 매개변수: key (String): 저장 키, value (String): 저장할 값. 반환값: 항상 true.
  @override
  Future<bool> setString(String key, String value) async {
    writtenKeys.add(key);
    values[key] = value;
    return true;
  }

  // 함수이름: remove
  // 함수역할: 삭제 호출을 기록하고 값을 메모리 맵에서 지운다.
  // 매개변수: key (String): 지울 저장 키. 반환값: 항상 true.
  @override
  Future<bool> remove(String key) async {
    removedKeys.add(key);
    values.remove(key);
    return true;
  }

  // 함수이름: noSuchMethod
  // 함수역할: 이 테스트가 쓰지 않는 저장소 기능이 호출되면 바로 실패하게 한다.
  // 매개변수: invocation (Invocation): 구현하지 않은 호출. 반환값: 없음; 항상 예외.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// 함수이름: main
// 함수역할:
// - 보호자별 환자 별칭과 알림 캐시 정리 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: setUp 콜백
  // 함수역할:
  // - 각 테스트 전에 메모리 설정 저장소를 비워 사용자 캐시를 격리한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 설정 저장소가 빈 상태로 초기화된다.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 환자 별칭이 없으면 짧은 기본 식별명을 사용한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 같은 보호자의 환자별 별칭을 독립적으로 저장한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 연결 해제된 환자의 별칭과 알림 캐시만 제거한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
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

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 영어 화면에는 영어 기본 식별명을 만들고, 저장된 별칭은 언어와 무관하게 그대로 쓴다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('영어 화면에는 영어 기본 식별명을 사용한다', () async {
    final preferences = await SharedPreferences.getInstance();

    expect(
      CaregiverPatientLocalStateService.resolveLabel(
        preferences,
        caregiverHash: 'caregiver_test',
        patientHash: 'patient_alpha',
        isEnglish: true,
      ),
      'Patient LPHA',
    );
    expect(
      CaregiverPatientLocalStateService.fallbackLabel('', isEnglish: true),
      'Linked patient',
    );
    expect(
      CaregiverPatientLocalStateService.fallbackLabel('abc', isEnglish: true),
      'Patient ABC',
    );

    // 별칭을 지우면 요청한 언어의 기본 식별명을 돌려주고 저장소에는 남기지 않는다.
    await CaregiverPatientLocalStateService.saveLabel(
      preferences,
      caregiverHash: 'caregiver_test',
      patientHash: 'patient_alpha',
      label: 'Mom',
    );
    expect(
      CaregiverPatientLocalStateService.resolveLabel(
        preferences,
        caregiverHash: 'caregiver_test',
        patientHash: 'patient_alpha',
        isEnglish: true,
      ),
      'Mom',
    );
    final clearedLabel = await CaregiverPatientLocalStateService.saveLabel(
      preferences,
      caregiverHash: 'caregiver_test',
      patientHash: 'patient_alpha',
      label: '  ',
      isEnglish: true,
    );
    expect(clearedLabel, 'Patient LPHA');
    expect(
      preferences.getString(
        'caregiver_patient_label.caregiver_test.patient_alpha',
      ),
      isNull,
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 저장된 값과 같은 별칭을 다시 저장하거나 없는 별칭을 지울 때 저장소에 쓰지 않는다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('값이 바뀌지 않은 별칭은 저장소에 다시 쓰지 않는다', () async {
    final preferences = _RecordingPreferences();
    const key = 'caregiver_patient_label.caregiver_test.patient_a';

    // 함수이름: save
    // 함수역할: 같은 보호자·환자 쌍에 별칭을 저장한다.
    // 매개변수: label (String): 저장할 별칭. 반환값: 화면에 표시할 이름.
    Future<String> save(String label) =>
        CaregiverPatientLocalStateService.saveLabel(
          preferences,
          caregiverHash: 'caregiver_test',
          patientHash: 'patient_a',
          label: label,
        );

    expect(await save('어머니'), '어머니');
    expect(await save('어머니'), '어머니');
    // 공백만 다른 입력은 정리 후 같은 값이므로 쓰지 않는다.
    expect(await save('  어머니\n'), '어머니');
    expect(preferences.writtenKeys, [key]);

    expect(await save('엄마'), '엄마');
    expect(preferences.writtenKeys, [key, key]);

    expect(await save(''), '환자 NT_A');
    expect(await save(''), '환자 NT_A');
    expect(preferences.removedKeys, [key]);
    expect(preferences.values, isEmpty);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 다른 파일이 함께 쓰는 저장 키 접두어가 기존 저장 형식과 같다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 접두어가 바뀌면 테스트가 실패한다.
  test('저장 키 접두어는 기존 저장 형식과 같다', () {
    expect(
      CaregiverPatientLocalStateService.patientLabelKeyPrefix,
      'caregiver_patient_label.',
    );
    expect(
      CaregiverPatientLocalStateService.linkedPatientsKeyPrefix,
      'caregiver_linked_patients.',
    );
    expect(
      CaregiverPatientLocalStateService.alertKeyPrefix,
      'caregiver_alert.',
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 기대 동작: 연동 목록의 표시 이름은 서버 별칭을 우선하고 별칭이 없는 환자에게만 요청한 언어의 기본 식별명을 쓴다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('연동 목록 표시 이름은 요청한 언어의 기본 식별명을 사용한다', () async {
    const control = ManageCaregiverPatientLocalState();
    const links = [
      PatientCaregiverLink(
        linkId: 1,
        patientHash: 'patient_a',
        caregiverHash: 'caregiver_test',
        patientAlias: '어머니',
        linkStatus: true,
      ),
      PatientCaregiverLink(
        linkId: 2,
        patientHash: 'patient_b',
        caregiverHash: 'caregiver_test',
        patientAlias: '',
        linkStatus: true,
      ),
      PatientCaregiverLink(
        linkId: 3,
        patientHash: 'patient_c',
        caregiverHash: 'caregiver_other',
        linkStatus: true,
      ),
    ];

    expect(
      await control.loadLabels(
        caregiverHash: 'caregiver_test',
        links: links,
        isEnglish: true,
      ),
      {'patient_a': '어머니', 'patient_b': 'Patient NT_B'},
    );
    expect(
      await control.loadLabels(caregiverHash: 'caregiver_test', links: links),
      {'patient_a': '어머니', 'patient_b': '환자 NT_B'},
    );
    expect(control.fallbackLabel('patient_b', isEnglish: true), 'Patient NT_B');
    expect(control.fallbackLabel('patient_b'), '환자 NT_B');
    expect(
      await control.loadLabel(
        caregiverHash: 'caregiver_test',
        patientHash: 'patient_b',
        isEnglish: true,
      ),
      'Patient NT_B',
    );
    expect(
      await control.saveLabel(
        caregiverHash: 'caregiver_test',
        patientHash: 'patient_a',
        label: '',
        isEnglish: true,
      ),
      'Patient NT_A',
    );
  });
}
