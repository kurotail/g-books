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
import 'services/api_game_state_service.dart';
import 'services/quiz_service.dart';
import 'services/collection_progress_service.dart';
import 'services/teacher_service.dart';
import 'services/api_client.dart';
import 'config/app_config.dart';

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

  // 學生端顯示用古蹟設定（slot 幾何 / 原料名稱 / 等級）先以 assets 初值套用。啟動時
  // 尚未登入、無法向後端取 building（需 JWT），故顯示走本機初值；功能規則（可放哪、
  // 難度給哪種原料）一律以後端 building 為準。管理者於後端編輯後，學生重登即更新。
  await Future.wait(heritageIds.map((hid) async {
    applyHeritageConfig(hid, await seedHeritageConfigFromAssets(hid));
  }));

  // 後端串接：所有服務共用同一個 ApiClient（持有 JWT、自動換新）。kUseBackend=false
  // 時改用本機 mock，App 可離線開發；後端資料備妥後翻成 true 即整組切過去、UI 不變。
  final apiClient = ApiClient();

  // 管理者古蹟編輯器的設定服務：後端模式存進 gb_api 的 building（需管理者登入），
  // 離線開發則用本機檔假後端。
  final HeritageConfigService configService = kUseBackend
      ? ApiHeritageConfigService(apiClient)
      : LocalHeritageConfigService();

  final appState = AppState(apiClient: apiClient, useBackend: kUseBackend);

  // 背包 / 放置：mock 與 API 共用同一套（後端形狀的）DTO，差別僅在傳輸。
  final HeritageSyncService syncService =
      kUseBackend ? ApiHeritageSyncService(apiClient) : MockHeritageSyncService();
  final boardController = HeritageBoardController(syncService);

  // 採集取題 / 作答。
  final QuizService quizService =
      kUseBackend ? ApiQuizService(apiClient) : MockQuizService();

  // 遊戲狀態（老師端切換階段 + 倒數開始時間）。mock 版先還原 / 建立場次，讓重啟後能
  // 接續同場次的採集進度；API 版直接讀後端 `/api/state` 的 updated_at。
  final GameStateService gameStateService;
  if (kUseBackend) {
    gameStateService = ApiGameStateService(apiClient);
  } else {
    final mock = MockGameStateService();
    await mock.init();
    gameStateService = mock;
  }

  // 教師控制台：階段切換 / 學生帳號 / 小組設定。mock 版直接推給上面的 gameState。
  final TeacherService teacherService = kUseBackend
      ? ApiTeacherService(apiClient)
      : MockTeacherService(gameStateService as MockGameStateService);

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
        Provider<TeacherService>.value(value: teacherService),
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
