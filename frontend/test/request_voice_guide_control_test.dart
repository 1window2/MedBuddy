// File Name: request_voice_guide_control_test.dart
// Role: Regression coverage for remote and local medication voice guides and language consistency.

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
        medicationDetail.voiceGuideText,
        'Saved tablet\n'
        '복용 방법. Take after meals\n'
        '주의사항. May cause drowsiness',
      );
      expect(medicationDetail.voiceGuideText, isNot(contains('Pain relief')));
      expect(
        medicationDetail.voiceGuideText,
        isNot(contains('Drink enough water.')),
      );
    },
  );

  // 함수이름: test 콜백
  // 함수역할:
  // - 하루 세 번 복용 문구에서 상세 복용량 안내 세 줄을 만들고 기본 음성 안내에서는 복용량을 제외하는지 검증한다.
  // 매개변수:
  // - 없음.
  // 반환값:
  // - 없음; 기대 조건 불일치 시 테스트가 실패한다.
  test('MedicationDetail derives dosage guide lines from frequency labels', () {
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
      medicationDetail.detailedDosageGuideLines.where(
        // 함수이름: where 콜백
        // 함수역할:
        // - 명시적 한 알 복용량을 포함한 상세 복용 안내 문장을 선택한다.
        // 매개변수:
        // - line (String): 한 번 복용량을 검사할 상세 복용 안내 문장.
        // 반환값:
        // - 해당 문장에 한 알 복용량이 포함되는지 여부.
        (line) => line.contains('1 tablet'),
      ),
      hasLength(3),
    );
    expect(medicationDetail.voiceGuideText, isNot(contains('1 tablet')));
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
        contains('Warnings. No information'),
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

      expect(usedText, contains('How to take it.'));
      expect(usedText, contains('Warnings.'));
      expect(usedText, isNot(contains('복용 방법')));
      expect(spokenText, usedText);
      control.dispose();
    },
  );
}
