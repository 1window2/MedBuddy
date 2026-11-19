// File Name: link.dart
// Role: Capture patient code polling and completion with synthetic exact-code status.
// Function Name: main
// Description: Register code waiting and automatic-success captures without networking.
// Parameters: None.
// Returns: void; initializes isolated preferences and the linking fixture.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(captureFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  // Function Name: guide patient code automatic completion
  // Description: Render a synthetic code, matching completion and linked list.
  // Parameters: tester drives the isolated patient-link boundary.
  // Returns: Future<void>; captures PNGs without modifying any real link.
  testWidgets('guide patient code automatic completion', (tester) async {
    captureViewport(tester);
    final control = _Control();
    await tester.pumpWidget(_app(control, english: false));
    await captureScreen(tester, 'patient-link-home');
    await _open(tester, english: false);
    await captureScreen(tester, 'patient-code-waiting');
    control.reply(PatientLinkCodeState.linked);
    await tester.pumpAndSettle();
    expect(find.text('연동 완료'), findsOneWidget);
    await captureScreen(tester, 'patient-code-auto-success');
    await tester.tap(find.byKey(const Key('patient-link-result-confirm')));
    await tester.pumpAndSettle();
    await captureScreen(tester, 'patient-linked-list');
    await tester.pumpWidget(const SizedBox.shrink());
    control.dispose();
  });
}
