// Basic deterministic widget smoke test for LumiSense.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lumisense/providers/history_provider.dart';
import 'package:lumisense/screens/history_screen.dart';

void main() {
  testWidgets('History screen empty-state smoke test',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ChangeNotifierProvider<HistoryProvider>(
        create: (_) => HistoryProvider(prefs: prefs),
        child: const MaterialApp(
          home: HistoryScreen(),
        ),
      ),
    );

    expect(find.text('History'), findsOneWidget);
    expect(
      find.text('No history yet. Use Read or Identify in camera mode to save entries.'),
      findsOneWidget,
    );
  });
}
