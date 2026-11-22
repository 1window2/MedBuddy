// File Name: chat.dart
// Role: Capture individual and slot-wide requests with an in-memory dose outbox.
// Function Name: main
// Description: Register individual and slot request captures without real delivery.
// Parameters: None.
// Returns: void; initializes isolated preferences, fonts and two fixture tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(captureFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final individual in [true, false]) {
    // Function Name: guide chat request scope
    // Description: Assert recording scope and capture request/completion states.
    // Parameters: tester is the widget driver; individual selects the request kind.
    // Returns: Future<void>; fails if the fixture records the wrong medications.
    testWidgets('guide chat request scope individual=$individual', (tester) async {
      captureViewport(tester);
      final harness = await _attachChatDoseSync([
        ..._cachedTwoSlotSchedule,
        const MedicationSchedule(medicationID: '93', medicationName: '다른 아침 약', scheduleSlotKeys: ['morning']),
      ]);
      final slot = ChatScheduleContext(scheduleDate: '2026-09-21', slotKey: 'morning', alarmTime: '08:00',
        alarmEnabled: true, completedCount: 0, totalCount: individual ? 1 : 2, medications: [
          const ChatMedicationContext(medicationId: 91, medicationName: '테스트정', dosagePerTime: '1정', scheduleSlotKeys: ['morning']),
          if (!individual) const ChatMedicationContext(medicationId: 93, medicationName: '다른 아침 약', dosagePerTime: '1정', scheduleSlotKeys: ['morning']),
        ]);
      final control = _TakenChatControl(historyMessages: [ChatMessage(
        messageId: 70, linkId: 17, senderHash: 'caregiver-a', clientMessageId: 'guide-request',
        body: individual ? '테스트정 복용하셨나요?' : '아침 약을 모두 복용하셨나요?', createdAt: _doseNow,
        messageKind: individual ? ChatMessageKind.medicationCheckRequest : ChatMessageKind.slotCheckRequest,
        scheduleContext: individual ? null : slot,
        medicationCheckContexts: individual ? [slot] : const [],
      )]);
      final realtime = _FakeRealtimeService();
      await _pumpPatientChat(tester, harness, control: control, realtime: realtime);
      final stem = individual ? 'chat-medication' : 'chat-slot';
      await captureScreen(tester, '$stem-request');
      await tester.tap(find.byKey(const ValueKey('chat-confirm-dose-70-morning')));
      await tester.pumpAndSettle();
      await captureScreen(tester, '$stem-completed');
      expect(harness.service.schedules.firstWhere((s) => s.medicationID == '93').isSlotCompleted('morning'), !individual);
      await _closeChat(tester, harness, control: control, realtime: realtime);
    });
  }
}
