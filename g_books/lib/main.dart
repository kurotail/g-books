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
import 'services/account_service.dart';
import 'services/avatar_service.dart';
import 'services/api_client.dart';
import 'config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 預解碼 logo 與各頁背景進快取，避免首次顯示時露出純色底（此時尚無 BuildContext）。
  await Future.wait([
    _warmImage('assets/logo.png'),
    _warmImage('assets/images/bg_login.png'),
    _warmImage('assets/images/bg_group_info.png'),
  ]);

  final heritageIds = mockHeritages.map((h) => h.id).toList();

  // 讀 assets 列出各古蹟可用的原料圖片 id（決定「有哪些原料」）；其餘設定（slot 幾何 /
  // 名稱 / 等級 / 可放對應）由後端 building 於學生登入後載入（見 [StudentConfigLoader]）。
  await loadComponentImageIds(heritageIds);

  // 所有服務共用同一個 ApiClient（持 JWT、自動換新）。kUseBackend=false 走本機 mock，
  // 可離線開發；後端備妥後翻 true 即整組切換、UI 不變。
  final apiClient = ApiClient();

  // 管理者編輯器的設定服務：後端模式存進 gb_api building，離線用本機檔假後端。
  final HeritageConfigService configService = kUseBackend
      ? ApiHeritageConfigService(apiClient)
      : LocalHeritageConfigService();

  // 學生端設定載入器：登入後依該組 building_id 取後端設定並快取本機（離線回退）。
  final studentConfigLoader =
      StudentConfigLoader(kUseBackend ? apiClient : null);

  // 頭像：後端走 POST /api/image + pfp 端點；離線用本機預覽。
  final AvatarService avatarService =
      kUseBackend ? ApiAvatarService(apiClient) : MockAvatarService();

  final appState = AppState(
    apiClient: apiClient,
    useBackend: kUseBackend,
    configLoader: studentConfigLoader,
    avatarService: avatarService,
  );

  // 背包 / 放置：mock 與 API 共用同一套後端形狀 DTO，差別僅在傳輸。
  final HeritageSyncService syncService =
      kUseBackend ? ApiHeritageSyncService(apiClient) : MockHeritageSyncService();
  final boardController = HeritageBoardController(syncService);

  // 採集取題 / 作答。
  final QuizService quizService =
      kUseBackend ? ApiQuizService(apiClient) : MockQuizService();

  // 遊戲狀態（階段 + 倒數開始時間）。mock 版還原 / 建立場次以便重啟後接續採集進度；
  // API 版讀後端 /api/state。
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

  // 管理者後台：教師帳號管理（role=1）。mock 版操作本機種子。
  final AccountService accountService =
      kUseBackend ? ApiAccountService(apiClient) : MockAccountService();

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
        Provider<AccountService>.value(value: accountService),
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
