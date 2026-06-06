import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:g_books/features/auth/login_screen.dart';
import 'package:g_books/state/app_state.dart';

void main() {
  testWidgets('Login screen renders name + seat fields', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text('姓名'), findsOneWidget);
    expect(find.text('座號'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
