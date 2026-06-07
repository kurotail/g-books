import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'data/component_data.dart';
import 'data/heritage_data.dart';
import 'data/slot_data.dart';
import 'state/app_state.dart';
import 'state/heritage_board_controller.dart';
import 'services/heritage_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 載入各古蹟的 slot 幾何與元件→slot 對應（assets/data/...）。
  final heritageIds = mockHeritages.map((h) => h.id).toList();
  await loadHeritageSlots(heritageIds);
  await loadComponentSlots(heritageIds);
  final appState = AppState();
  // 本機 mock 同步服務；之後替換為 ApiHeritageSyncService 即可，UI 不需更動。
  final boardController = HeritageBoardController(MockHeritageSyncService());
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<HeritageBoardController>.value(
          value: boardController,
        ),
      ],
      child: GBooksApp(appState: appState),
    ),
  );
}
