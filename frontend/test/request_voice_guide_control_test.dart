// File Name: request_voice_guide_control_test.dart
// Role: Verifies voice guide control API fallback and TTS delegation.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/controls/request_voice_guide_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/medication_guide_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

void main() {
  test('MedicationGuide preserves AI guide from medication detail', () {
    final medicationGuide = MedicationGuide.fromMedicationDetail(
      const MedicationDetail(
        itemName: 'Saved tablet',
        efficacy: 'Pain relief',
        usageMethod: 'Take after meals',
        warning: 'May cause drowsiness',
        aiGuide: 'Drink enough water.',
      ),
    );

    expect(medicationGuide.aiGuide, 'Drink enough water.');
    expect(medicationGuide.voiceGuideText, contains('Drink enough water.'));
  });

  test('requestVoiceGuide speaks backend voice guide text', () async {
    late Map<String, dynamic> requestBody;
    var spokenText = '';
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
      speaker: (
        String text,
        UserSetting userSetting, {
        void Function()? onComplete,
      }) async {
        spokenText = text;
        onComplete?.call();
      },
    );

    final usedText = await control.requestVoiceGuide(
      medicationGuide: const MedicationGuide(
        itemName: 'Test tablet',
        efficacy: 'Pain relief',
        usageMethod: 'Take after meals',
        warning: 'May cause drowsiness',
        aiGuide: 'Drink enough water.',
      ),
      userSetting: const UserSetting(language: 'en'),
    );

    expect(requestBody['item_name'], 'Test tablet');
    expect(requestBody['ai_guide'], 'Drink enough water.');
    expect(requestBody['language'], 'en');
    expect(usedText, 'Medication: Test tablet');
    expect(spokenText, 'Medication: Test tablet');
    control.dispose();
  });

  test('requestVoiceGuide falls back to local guide text on backend failure',
      () async {
    var spokenText = '';
    final client = MockClient((http.Request request) async {
      return http.Response('{"detail":"down"}', 500);
    });
    final control = RequestVoiceGuide(
      baseUrl: 'http://localhost',
      client: client,
      speaker: (
        String text,
        UserSetting userSetting, {
        void Function()? onComplete,
      }) async {
        spokenText = text;
      },
    );

    final usedText = await control.requestVoiceGuide(
      medicationGuide: const MedicationGuide(
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
    expect(usedText, contains('Pain relief'));
    expect(usedText, contains('Take after meals'));
    expect(usedText, contains('Drink enough water.'));
    expect(usedText.trim(), isNotEmpty);
    expect(spokenText, usedText);
    control.dispose();
  });
}
