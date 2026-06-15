import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'data/component_data.dart';
import 'data/heritage_data.dart';
import 'state/app_state.dart';
import 'state/heritage_board_controller.dart';
import 'services/heritage_config_service.dart';
import 'services/heritage_sync_service.dart';
import 'services/game_state_service.dart';
import 'services/quiz_service.dart';
import 'services/collection_progress_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先把載入畫面的 logo 與各頁背景解碼進快取，避免：出征後載入畫面 logo 尚未載入
  // 而空白、進小組資訊時 bg_group_info 還在載入而露出純色底（這時還沒有 BuildContext，
  // 故用 ImageConfiguration.empty 解析）。
  await Future.wait([
    _warmImage('assets/logo.png'),
    _warmImage('assets/images/bg_login.png'),
    _warmImage('assets/images/bg_group_info.png'),
  ]);

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
  // 遊戲狀態（老師端切換階段）與題目服務，現階段皆為本機 mock。
  // gameState 先還原 / 建立場次，讓重啟後能接續同場次的採集進度。
  final gameStateService = MockGameStateService();
  await gameStateService.init();
  final quizService = MockQuizService();
  final collectionProgressService = LocalCollectionProgressService();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<HeritageBoardController>.value(
          value: boardController,
        ),
        Provider<HeritageConfigService>.value(value: configService),
        Provider<GameStateService>.value(value: gameStateService),
        Provider<QuizService>.value(value: quizService),
        Provider<CollectionProgressService>.value(
          value: collectionProgressService,
        ),
      ],
      child: GBooksApp(appState: appState),
    ),
  );
}

/// 在 `runApp` 前把資產圖解碼進全域 ImageCache（無 context 版的 precache）。
/// 缺圖以 onError 吞掉，避免卡住啟動。
Future<void> _warmImage(String asset) {
  final completer = Completer<void>();
  final stream = AssetImage(asset).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void done() {
    stream.removeListener(listener);
    if (!completer.isCompleted) completer.complete();
  }

  listener = ImageStreamListener(
    (_, _) => done(),
    onError: (_, _) => done(),
  );
  stream.addListener(listener);
  return completer.future;
}
