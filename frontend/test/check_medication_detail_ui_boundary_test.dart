// File Name: check_medication_detail_ui_boundary_test.dart
// Role: Regression coverage for the read-aloud control of the medication detail screen when the
//   app moves to the background or the screen closes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medbuddy_frontend/boundaries/check_medication_detail_ui_boundary.dart';
import 'package:medbuddy_frontend/controls/request_voice_guide_control.dart';
import 'package:medbuddy_frontend/entities/medication_detail_entity.dart';
import 'package:medbuddy_frontend/entities/user_setting_entity.dart';

// Class Name: _RecordingVoiceGuide
// Role: Voice-guide control fake that keeps playback running until it is stopped.
// Responsibilities:
// - Count start, stop and dispose requests without contacting a server or a speech engine.
// - Keep a started guide pending so the screen stays in its reading state.
// Attributes:
// - startCount (int): Number of guides the screen started.
// - stopCount (int): Number of stop requests received.
// - disposeCount (int): Number of dispose requests received.
class _RecordingVoiceGuide extends RequestVoiceGuide {
  int startCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  Completer<String>? _playback;

  // Function Name: _RecordingVoiceGuide
  // Description:
  // - Binds the fake to an offline client and a silent speaker so no platform channel is used.
  // Parameters:
  // - None.
  // Returns:
  // - _RecordingVoiceGuide: the initialized instance.
  _RecordingVoiceGuide()
    : super(
        baseUrl: 'http://medbuddy.test',
        client: MockClient((_) async => http.Response('{}', 500)),
        speaker: (text, userSetting, {onComplete}) async {},
      );

  // Function Name: requestVoiceGuide
  // Description:
  // - Counts the start and stays pending, as an utterance that is still being read does.
  // Parameters:
  // - medicationDetail (MedicationDetail): Medication whose guide is requested; not used.
  // - userSetting (UserSetting): Reading settings; not used.
  // - onComplete (void Function()?): Completion receiver; never called by this fake.
  // Returns:
  // - A future that completes only when the guide is stopped.
  @override
  Future<String> requestVoiceGuide({
    required MedicationDetail medicationDetail,
    required UserSetting userSetting,
    void Function()? onComplete,
  }) {
    startCount += 1;
    final playback = Completer<String>();
    _playback = playback;
    return playback.future;
  }

  // Function Name: stop
  // Description:
  // - Counts the stop request and ends the pending guide.
  // Parameters:
  // - None.
  // Returns:
  // - Future<void>; completes when the pending guide has ended.
  @override
  Future<void> stop() async {
    stopCount += 1;
    final playback = _playback;
    _playback = null;
    if (playback != null && !playback.isCompleted) {
      playback.complete('');
    }
  }

  // Function Name: dispose
  // Description:
  // - Counts the dispose request before releasing the base control.
  // Parameters:
  // - None.
  // Returns:
  // - No value.
  @override
  void dispose() {
    disposeCount += 1;
    super.dispose();
  }
}

// Function Name: _pumpDetail
// Description:
// - Shows the medication detail screen with the given voice-guide control.
// Parameters:
// - tester (WidgetTester): Widget harness for rendering and interaction.
// - voiceGuide (_RecordingVoiceGuide): Control the screen uses for reading aloud.
// Returns:
// - Future<void>; completes when the screen has settled.
Future<void> _pumpDetail(
  WidgetTester tester,
  _RecordingVoiceGuide voiceGuide,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CheckMedicationDetailUI(
        medicationDetail: const MedicationDetail(
          itemName: '읽기 테스트정',
          efficacy: '테스트 효능',
          usageMethod: '하루 한 번 복용하세요.',
          warning: '주의사항을 확인하세요.',
        ),
        userSetting: const UserSetting(),
        requestVoiceGuide: voiceGuide,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Function Name: main
// Description:
// - Registers the read-aloud lifecycle cases of the medication detail screen.
// Parameters:
// - None.
// Returns:
// - No value; the test framework executes the registered cases.
void main() {
  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: reading aloud stops and the button returns to its idle label when the
  //   app is paused.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('reading aloud stops when the app is paused', (tester) async {
    final voiceGuide = _RecordingVoiceGuide();
    addTearDown(voiceGuide.dispose);
    // Function Name: tearDown callback
    // Description: Returns the test binding to the resumed state for later cases. Parameters: None. Returns: None.
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await _pumpDetail(tester, voiceGuide);

    await tester.tap(find.text('큰 소리로 읽어주세요'));
    await tester.pump();
    expect(voiceGuide.startCount, 1);
    expect(find.text('읽기 중지'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(voiceGuide.stopCount, 0);
    expect(find.text('읽기 중지'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();

    expect(voiceGuide.stopCount, 1);
    expect(find.text('큰 소리로 읽어주세요'), findsOneWidget);
    expect(find.text('읽기 중지'), findsNothing);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: pausing the app while nothing is read does not send a stop request.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('pausing the app while idle does not request a stop', (
    tester,
  ) async {
    final voiceGuide = _RecordingVoiceGuide();
    addTearDown(voiceGuide.dispose);
    // Function Name: tearDown callback
    // Description: Returns the test binding to the resumed state for later cases. Parameters: None. Returns: None.
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await _pumpDetail(tester, voiceGuide);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(voiceGuide.stopCount, 0);
  });

  // Function Name: testWidgets callback
  // Description:
  // - Expected behavior: closing the screen stops playback, leaves a control supplied by the
  //   caller undisposed, and no longer reacts to lifecycle changes.
  // Parameters:
  // - tester (WidgetTester): Widget harness for rendering, interaction, and assertions.
  // Returns:
  // - Future<void>; completes when the scenario assertions pass, or fails with the test error.
  testWidgets('closing the screen stops playback and keeps a supplied '
      'control undisposed', (tester) async {
    final voiceGuide = _RecordingVoiceGuide();
    // Function Name: tearDown callback
    // Description: Returns the test binding to the resumed state for later cases. Parameters: None. Returns: None.
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await _pumpDetail(tester, voiceGuide);
    await tester.tap(find.text('큰 소리로 읽어주세요'));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(voiceGuide.stopCount, 1);
    expect(voiceGuide.disposeCount, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(voiceGuide.stopCount, 1);
    voiceGuide.dispose();
  });
}
