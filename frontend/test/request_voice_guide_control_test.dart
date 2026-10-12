// File Name: request_voice_guide_control_test.dart
// Role: Regression coverage for remote and local medication voice guides and language consistency.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/request_voice_guide_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// 함수이름: main
// 함수역할:
// - 서버·로컬 복약 음성 안내와 언어 일관성 검증 사례와 테스트 대역을 등록한다.
// 매개변수:
// - 없음.
// 반환값:
// - 없음; 등록된 사례는 테스트 프레임워크가 실행한다.
void main() {
  // 함수이름: 문구 조회 중 중지 테스트
  // 함수역할: 안내 문구를 받아오는 동안 중지하면 응답이 도착한 뒤에도 읽기를 시작하지 않고, 다음 요청은 늦게 도착해 보관된 문구를 서버에 다시 묻지 않고 정상적으로 읽는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('a voice guide stopped while its text is loading is not spoken', () async {
    final pendingResponses = <Completer<http.Response>>[];
    final spoken = <String>[];
    final client = MockClient((request) {
      final response = Completer<http.Response>();
      pendingResponses.add(response);
      return response.future;
    });
    addTearDown(client.close);
    final control = RequestVoiceGuide(
      baseUrl: 'http://localhost',
      client: client,
      speaker: (text, userSetting, {onComplete}) async => spoken.add(text),
    );
    const detail = MedicationDetail(
      itemName: 'Saved tablet',
      efficacy: '',
      usageMethod: 'Take after meals',
      warning: '',
    );
    http.Response guide(String text) => http.Response(
      jsonEncode({
        'data': {'voice_guide_text': text},
      }),
      200,
    );

    final stopped = control.requestVoiceGuide(
      medicationDetail: detail,
      userSetting: const UserSetting(),
    );
    await Future<void>.delayed(Duration.zero);
    await control.stop();
    pendingResponses.single.complete(guide('late guide'));
    await stopped;
    expect(spoken, isEmpty);

    await control.requestVoiceGuide(
      medicationDetail: detail,
      userSetting: const UserSetting(),
    );
    expect(spoken, ['late guide']);
    expect(pendingResponses, hasLength(1));
  });

  // 함수이름: 안내 문구 보관 테스트
  // 함수역할: 같은 약과 언어의 안내 문구는 한 번만 서버에 요청하고, 언어나 약 내용이 달라지면 다시 요청하는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('a resolved voice guide is reused per medication and language', () async {
    final requestedLanguages = <String>[];
    final spoken = <String>[];
    // 함수역할: 요청 언어를 기록하고 요청 순번이 담긴 안내 문구를 돌려준다. 매개변수: request. 반환값: HTTP 200 응답.
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      requestedLanguages.add(body['language'] as String);
      return http.Response(
        jsonEncode({
          'data': {
            'voice_guide_text':
                'guide ${requestedLanguages.length} ${body['item_name']}',
          },
        }),
        200,
      );
    });
    addTearDown(client.close);
    final control = RequestVoiceGuide(
      baseUrl: 'http://localhost',
      client: client,
      // 함수역할: 읽을 문구를 기록한다. 매개변수: text, userSetting, onComplete. 반환값: 기록 완료.
      speaker: (text, userSetting, {onComplete}) async => spoken.add(text),
    );
    const detail = MedicationDetail(
      itemName: 'Saved tablet',
      efficacy: '',
      usageMethod: 'Take after meals',
      warning: '',
    );

    for (var attempt = 0; attempt < 2; attempt += 1) {
      await control.requestVoiceGuide(
        medicationDetail: detail,
        userSetting: const UserSetting(),
      );
    }
    await control.requestVoiceGuide(
      medicationDetail: detail,
      userSetting: const UserSetting(language: 'en'),
    );
    await control.requestVoiceGuide(
      medicationDetail: detail.copyWith(itemName: 'Other tablet'),
      userSetting: const UserSetting(),
    );

    expect(requestedLanguages, ['ko', 'en', 'ko']);
    expect(spoken, [
      'guide 1 Saved tablet',
      'guide 1 Saved tablet',
      'guide 2 Saved tablet',
      'guide 3 Other tablet',
    ]);
  });

  // 함수이름: 연결 실패 뒤 보관 테스트
  // 함수역할: 서버에 연결하지 못해 만든 로컬 안내도 보관해 같은 안내를 다시 들을 때 요청 제한 시간을 기다리지 않는지 검증한다.
  // 매개변수: 없음. 반환값: 비동기 검증 완료; 불일치 시 테스트 실패.
  test('a local voice guide is reused instead of asking the server again', () async {
    var requestCount = 0;
    final spoken = <String>[];
    // 함수역할: 요청 횟수를 세고 연결 실패를 재현한다. 매개변수: request. 반환값: 연결 예외.
    final client = MockClient((request) async {
      requestCount += 1;
      throw http.ClientException('offline');
    });
    addTearDown(client.close);
    final control = RequestVoiceGuide(
      baseUrl: 'http://localhost',
      client: client,
      // 함수역할: 읽을 문구를 기록한다. 매개변수: text, userSetting, onComplete. 반환값: 기록 완료.
      speaker: (text, userSetting, {onComplete}) async => spoken.add(text),
    );
    const detail = MedicationDetail(
      itemName: 'Saved tablet',
      efficacy: '',
      usageMethod: 'Take after meals',
      warning: '',
    );

    for (var attempt = 0; attempt < 2; attempt += 1) {
      await control.requestVoiceGuide(
        medicationDetail: detail,
        userSetting: const UserSetting(),
      );
    }

    expect(requestCount, 1);
    expect(spoken, [
      '약 이름: Saved tablet\n복용 방법: Take after meals',
      '약 이름: Saved tablet\n복용 방법: Take after meals',
    ]);
  });

  // 함수이름: 서버 형식 일치 테스트
  // 함수역할: 로컬 안내가 서버와 같은 항목명·구분 기호를 쓰고 빈 항목을 생략하며, 세 항목이 모두 비면 이름 확인 문구만 안내하는지 검증한다.
  // 매개변수: 없음. 반환값: 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('MedicationDetail local voice guide follows the server template', () {
    const full = MedicationDetail(
      itemName: ' Saved tablet ',
      efficacy: 'Pain relief',
      usageMethod: ' Take after meals ',
      warning: ' May cause drowsiness ',
    );
    expect(
      full.voiceGuideTextForLanguage('en'),
      'Medication: Saved tablet\n'
      'How to take: Take after meals\n'
      'Warning: May cause drowsiness',
    );
    const warningOnly = MedicationDetail(
      itemName: 'Saved tablet',
      efficacy: '',
      usageMethod: ' ',
      warning: 'May cause drowsiness',
    );
    expect(
      warningOnly.voiceGuideTextForLanguage('ko'),
      '약 이름: Saved tablet\n주의사항: May cause drowsiness',
    );
    const blank = MedicationDetail(
      itemName: ' ',
      efficacy: '',
      usageMethod: '',
      warning: '',
    );
    expect(blank.voiceGuideTextForLanguage('ko'), '약 이름: 약품명 확인 필요');
    expect(
      blank.voiceGuideTextForLanguage('en'),
      'Medication: Medication name needs review',
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 로컬 복약 음성 안내에 약명·복용법·주의사항만 포함하고 효능과 추가 안내를 제외하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test(
    'MedicationDetail limits local voice guide to the three required parts',
    () {
      const medicationDetail = MedicationDetail(
        itemName: 'Saved tablet',
        efficacy: 'Pain relief',
        usageMethod: 'Take after meals',
        warning: 'May cause drowsiness',
        aiGuide: 'Drink enough water.',
      );

      expect(medicationDetail.aiGuide, 'Drink enough water.');
      expect(
        medicationDetail.voiceGuideTextForLanguage('ko'),
        '약 이름: Saved tablet\n'
        '복용 방법: Take after meals\n'
        '주의사항: May cause drowsiness',
      );
      expect(
        medicationDetail.voiceGuideTextForLanguage('ko'),
        isNot(contains('Pain relief')),
      );
      expect(
        medicationDetail.voiceGuideTextForLanguage('ko'),
        isNot(contains('Drink enough water.')),
      );
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 구조화된 복용량이 있어도 기본 음성 안내에서는 복용량을 제외하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('MedicationDetail voice guide excludes structured dosage', () {
    const medicationDetail = MedicationDetail(
      itemName: 'Saved tablet',
      efficacy: 'Pain relief',
      usageMethod: 'Take after meals',
      warning: 'May cause drowsiness',
      dosagePerTime: '1 tablet',
      dailyFrequency: '1일 3회',
      totalDays: '5 days',
    );

    expect(
      medicationDetail.voiceGuideTextForLanguage('ko'),
      isNot(contains('1 tablet')),
    );
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 하루 횟수나 일 단위가 아닌 복용 지시를 영어 문구로 바꿔 뜻을 달리 전하지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('MedicationDetail keeps directions it cannot read as a daily count', () {
    List<String> lines(String dailyFrequency, String totalDays) =>
        MedicationDetail(
          itemName: 'Test tablet',
          efficacy: '',
          usageMethod: '',
          warning: '',
          dailyFrequency: dailyFrequency,
          totalDays: totalDays,
        ).compactDosageGuideLinesForLanguage('en');

    expect(lines('2일 1회', '2주'), [
      'Daily frequency · 2일 1회',
      'Duration · 2주',
    ]);
    expect(lines('주 1회', '1개월'), [
      'Daily frequency · 주 1회',
      'Duration · 1개월',
    ]);
    expect(lines('12시간마다', '7일분 (1주)'), [
      'Daily frequency · 12시간마다',
      'Duration · 7 days',
    ]);
    expect(lines('1일 3회 식후 30분', '0일'), [
      'Daily frequency · 1일 3회 식후 30분',
      'Duration · 0일',
    ]);
    expect(lines('1회', '1일'), [
      'Daily frequency · once daily',
      'Duration · 1 day',
    ]);
    expect(lines('2', '30'), [
      'Daily frequency · 2 times daily',
      'Duration · 30 days',
    ]);
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 구조화된 복용량과 대체 음성 안내의 항목명을 선택 언어로 표시하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test(
    'MedicationDetail localizes structural dosage and fallback voice labels',
    () {
      const medicationDetail = MedicationDetail(
        itemName: 'Test tablet',
        efficacy: '',
        usageMethod: '식후 복용',
        warning: '',
        dosagePerTime: '1정',
        dailyFrequency: '1일 3회',
        totalDays: '5일',
      );

      expect(
        medicationDetail.compactDosageGuideLinesForLanguage('en'),
        containsAll([
          'Dose per intake · 1 tablet',
          'Daily frequency · 3 times daily',
          'Duration · 5 days',
          'When to take · after meals',
        ]),
      );
      expect(
        medicationDetail.voiceGuideTextForLanguage('en'),
        'Medication: Test tablet\nHow to take: 식후 복용',
      );
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 서버가 반환한 복약 음성 안내 원문을 읽기 설정과 함께 재생하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test('requestVoiceGuide speaks backend voice guide text', () async {
    late Map<String, dynamic> requestBody;
    var spokenText = '';
    // Function Name: MockClient callback
    // Description:
    // - Assert voice-guide POST routing, capture its payload, and return padded English guide text.
    // Parameters:
    // - request (http.Request): HTTP request intercepted instead of reaching the server.
    // Returns:
    // - HTTP 200 containing the remote voice guide and language.
    final client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/voice-guide');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'voice_guide_text': '  Medication: Test tablet  ',
            'language': 'en',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final control = RequestVoiceGuide(
      baseUrl: 'http://localhost',
      client: client,
      speaker:
          // 함수이름: speaker 콜백
          // 함수역할:
          // - 음성 안내 문장을 기록한 뒤 선택적 완료 처리기를 실행한다.
          // 매개변수:
          // - text (String): 모의 재생에 전달한 음성 안내 문장.
          // - userSetting (UserSetting): 사례에 적용할 언어·글씨 크기·읽기 설정. 이 대역에서는 직접 사용하지 않는다.
          // - onComplete (void Function()?): 모의 음성 재생 완료 시 선택적으로 호출할 처리기.
          // 반환값:
          // - Future<void>; 문장 기록과 완료 안내가 끝난다.
          (
            String text,
            UserSetting userSetting, {
            void Function()? onComplete,
          }) async {
            spokenText = text;
            onComplete?.call();
          },
    );

    final usedText = await control.requestVoiceGuide(
      medicationDetail: const MedicationDetail(
        itemName: 'Test tablet',
        efficacy: 'Pain relief',
        usageMethod: 'Take after meals',
        warning: 'May cause drowsiness',
        aiGuide: 'Drink enough water.',
      ),
      userSetting: const UserSetting(language: 'en'),
    );

    expect(requestBody['item_name'], 'Test tablet');
    expect(
      requestBody.keys,
      unorderedEquals(['item_name', 'usage_method', 'warning', 'language']),
    );
    expect(requestBody['language'], 'en');
    expect(usedText, 'Medication: Test tablet');
    expect(spokenText, 'Medication: Test tablet');
    control.dispose();
  });

  // 함수이름: test 콜백
  // 함수역할:
  // - 서버 음성 안내 조회 실패 시 약 상세정보로 만든 로컬 안내를 재생하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'requestVoiceGuide falls back to local guide text on backend failure',
    () async {
      var spokenText = '';
      // Function Name: MockClient callback
      // Description:
      // - Complete the mocked HTTP request with status 500 and the fixed response body without network
      //   access.
      // Parameters:
      // - request (http.Request): HTTP request intercepted instead of reaching the server. Accepted but not
      //   consumed by this fixture.
      // Returns:
      // - Future<http.Response> with status 500.
      final client = MockClient((http.Request request) async {
        return http.Response('{"detail":"down"}', 500);
      });
      final control = RequestVoiceGuide(
        baseUrl: 'http://localhost',
        client: client,
        speaker:
            // 함수이름: speaker 콜백
            // 함수역할:
            // - 실제 발화 없이 대체 음성 안내 문장을 기록해 내용과 언어를 검사한다.
            // 매개변수:
            // - text (String): 모의 재생에 전달한 음성 안내 문장.
            // - userSetting (UserSetting): 사례에 적용할 언어·글씨 크기·읽기 설정. 이 대역에서는 직접 사용하지 않는다.
            // - onComplete (void Function()?): 모의 음성 재생 완료 시 선택적으로 호출할 처리기. 이 대역에서는 직접 사용하지 않는다.
            // 반환값:
            // - Future<void>; 발화할 문장 기록 완료.
            (
              String text,
              UserSetting userSetting, {
              void Function()? onComplete,
            }) async {
              spokenText = text;
            },
      );

      final usedText = await control.requestVoiceGuide(
        medicationDetail: const MedicationDetail(
          itemName: 'Fallback tablet',
          efficacy: 'Pain relief',
          usageMethod: 'Take after meals',
          warning: 'May cause drowsiness',
          dosagePerTime: '1 tablet',
          dailyFrequency: '3 times daily',
          totalDays: '3 days',
          aiGuide: 'Drink enough water.',
        ),
        userSetting: const UserSetting(language: 'ko'),
      );

      expect(usedText, contains('Fallback tablet'));
      expect(usedText, contains('Take after meals'));
      expect(usedText, contains('May cause drowsiness'));
      expect(usedText, isNot(contains('Pain relief')));
      expect(usedText, isNot(contains('1 tablet')));
      expect(usedText, isNot(contains('Drink enough water.')));
      expect(usedText.trim(), isNotEmpty);
      expect(spokenText, usedText);
      control.dispose();
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 영어 음성 안내의 대체 경로에도 한국어 항목명이 섞이지 않는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - Future<void>; 모든 기대 조건 확인 후 완료되며 불일치 시 테스트가 실패한다.
  test(
    'English voice guide fallback does not reintroduce Korean labels',
    () async {
      var spokenText = '';
      final control = RequestVoiceGuide(
        baseUrl: 'http://localhost',
        // 함수이름: MockClient 콜백
        // 함수역할:
        // - 네트워크 없이 HTTP 500 상태와 빈 JSON 객체를 제공한다.
        // 매개변수:
        // - _ (http.Request): 사용하지 않는 가로챈 HTTP 요청.
        // 반환값:
        // - HTTP 500 응답 Future.
        client: MockClient((_) async => http.Response('{}', 500)),
        speaker:
            // 함수이름: speaker 콜백
            // 함수역할:
            // - 실제 발화 없이 대체 음성 안내 문장을 기록해 내용과 언어를 검사한다.
            // 매개변수:
            // - text (String): 모의 재생에 전달한 음성 안내 문장.
            // - userSetting (UserSetting): 사례에 적용할 언어·글씨 크기·읽기 설정. 이 대역에서는 직접 사용하지 않는다.
            // - onComplete (void Function()?): 모의 음성 재생 완료 시 선택적으로 호출할 처리기. 이 대역에서는 직접 사용하지 않는다.
            // 반환값:
            // - Future<void>; 발화할 문장 기록 완료.
            (
              String text,
              UserSetting userSetting, {
              void Function()? onComplete,
            }) async {
              spokenText = text;
            },
      );

      final usedText = await control.requestVoiceGuide(
        medicationDetail: const MedicationDetail(
          itemName: 'Fallback tablet',
          efficacy: '',
          usageMethod: 'Take after meals',
          warning: 'May cause drowsiness',
        ),
        userSetting: const UserSetting(language: 'en'),
      );

      expect(
        usedText,
        'Medication: Fallback tablet\n'
        'How to take: Take after meals\n'
        'Warning: May cause drowsiness',
      );
      expect(usedText, isNot(contains('복용 방법')));
      expect(spokenText, usedText);
      control.dispose();
    },
  );
}
