// File Name: manual.dart
// Role: Append manual-entry captures to the isolated product test fixtures.
// Function Name: main
// Description: Register manual-entry and review-handoff captures without saving.
// Parameters: None.
// Returns: void; initializes test fonts and the fixture test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(captureFonts);
  // Function Name: guide manual entry review handoff
  // Description: Capture regular/as-needed entry, multiple items and review action.
  // Parameters: tester drives product forms using synthetic values.
  // Returns: Future<void>; writes PNGs or fails on unexpected widget errors.
  testWidgets('guide manual entry review handoff', (tester) async {
    captureViewport(tester);
    await _mount(tester, review: (_) => true, width: 412);
    await _enter(tester, 'name', '예시 복용약');
    await _enter(tester, 'dosage', '1');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, 1600));
    await tester.pumpAndSettle();
    await captureScreen(tester, 'manual-entry');
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await captureScreen(tester, 'manual-review-action');
    await _tap(tester, _field('as-needed'));
    await captureScreen(tester, 'manual-as-needed');
    await _tap(tester, _field('add'));
    await _enter(tester, 'name', '예시 복용약 2', 1);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await captureScreen(tester, 'manual-multiple');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
