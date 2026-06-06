// Basic smoke test for the G-BOOKS frontend.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:g_books/data/mock_data.dart';
import 'package:g_books/screens/login_screen.dart';
import 'package:g_books/state/app_state.dart';

void main() {
  testWidgets('Login screen renders name + seat fields', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => buildMockState(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    // Logo wordmark.
    expect(find.text('蹟不可師'), findsOneWidget);
    // Field labels.
    expect(find.text('姓名'), findsOneWidget);
    expect(find.text('座號'), findsOneWidget);
    // Two input fields.
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
