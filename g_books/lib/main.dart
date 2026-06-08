import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'data/component_data.dart';
import 'data/heritage_data.dart';
import 'state/app_state.dart';
import 'state/heritage_board_controller.dart';
import 'services/heritage_config_service.dart';
import 'services/heritage_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final heritageIds = mockHeritages.map((h) => h.id).toList();

  // 先讀 assets 列出各古蹟可用的原料圖片 id（決定「有哪些原料」）。
  await loadComponentImageIds(heritageIds);

  // 古蹟設定（slot / 對應 / 原料中繼資料）改由（假）後端供應：啟動時 fetch 並套用。
  // 首次會由現有 assets/dart 種子化並寫回本機檔，之後即以本機檔為準。
  final configService = LocalHeritageConfigService();
  await Future.wait(heritageIds.map((hid) async {
    applyHeritageConfig(hid, await configService.fetch(hid));
  }));

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
        Provider<HeritageConfigService>.value(value: configService),
      ],
      child: GBooksApp(appState: appState),
    ),
  );
}
