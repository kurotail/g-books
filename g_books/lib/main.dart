import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/mock_data.dart';
import 'state/app_state.dart';

void main() {
  runApp(
    ChangeNotifierProvider<AppState>(
      create: (_) => buildMockState(),
      child: const GBooksApp(),
    ),
  );
}
