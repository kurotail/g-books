import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: GBooksApp(appState: appState),
    ),
  );
}
