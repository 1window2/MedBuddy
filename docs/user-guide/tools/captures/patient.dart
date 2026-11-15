// File Name: patient.dart
// Role: Capture linked-patient target navigation using isolated fixture responses.
// Function Name: main
// Description: Register linked-patient navigation captures without modifying links.
// Parameters: None.
// Returns: void; initializes isolated preferences and the fixture test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(captureFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  // Function Name: guide linked patient destinations
  // Description: Capture target switching, read-only history and lookup failure.
  // Parameters: tester drives the boundary with two synthetic patient responses.
  // Returns: Future<void>; writes PNGs or fails on unexpected widget errors.
  testWidgets('guide linked patient destinations', (tester) async {
    captureViewport(tester);
    final h = _Harness(_Model(language: 'ko'));
    h.links.result = [_link(1, alias: '예시 환자 1'), _link(2, alias: '예시 환자 2')];
    await h.pump(tester, width: 412, height: 915);
    await tester.pumpAndSettle();
    await _tab(tester, 'schedule');
    await captureScreen(tester, 'patient-schedule');
    await tester.tap(find.byKey(const Key('schedule-patient-next')));
    await tester.pumpAndSettle();
    await captureScreen(tester, 'patient-schedule-second');
    await _tab(tester, 'medicationHistory');
    await captureScreen(tester, 'patient-history');
    await tester.tap(find.byKey(const Key('history-patient-previous')));
    await tester.pumpAndSettle();
    await captureScreen(tester, 'patient-history-first');
    h.links.fail = true;
    await h.refresh(tester);
    await captureScreen(tester, 'patient-link-error');
    await tester.pumpWidget(const SizedBox.shrink());
    h.model.dispose();
    h.links.dispose();
  });
}
