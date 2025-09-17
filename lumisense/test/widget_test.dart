// This is a basic Flutter widget test for LumiSense app.

import 'package:flutter_test/flutter_test.dart';

import 'package:lumisense/main.dart';

void main() {
  testWidgets('LumiSense app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LumiSenseApp());

    // Verify that our splash screen is displayed
    expect(find.text('LumiSense'), findsOneWidget);
    expect(find.text('Set Up My LumiSense'), findsOneWidget);
  });
}
