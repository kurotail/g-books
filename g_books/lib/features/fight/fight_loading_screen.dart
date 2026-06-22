import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/loading_screen.dart';
import '../../data/component_data.dart' show componentsOf;
import '../../data/heritage_data.dart';
import '../../data/models/heritage_model.dart';
import '../../services/fight_service.dart';
import '../../services/game_state_service.dart';
import '../../state/app_state.dart';
import 'fight_screen.dart';

class FightLoadingScreen extends StatefulWidget {
  const FightLoadingScreen({super.key});

  @override
  State<FightLoadingScreen> createState() => _FightLoadingScreenState();
}

class _FightLoadingScreenState extends State<FightLoadingScreen> {
  late final HeritageModel _heritage = mockHeritages.firstWhere(
    (h) => h.status == HeritageStatus.assigned,
    orElse: () => mockHeritages.first,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFight());
  }

  Future<void> _loadFight() async {
    final selfId = context.read<AppState>().currentGroup?.id ?? 0;
    final game = context.read<GameStateService>();
    final fight = context.read<FightService>();

    GameStateSnapshot? state;
    var groups = const <FightGroup>[];

    final dataJob = () async {
      try {
        state = await game.fetch();
      } catch (_) {}
      try {
        groups = await fight.fetchAllGroups(
          selfUserId: selfId,
          heritageId: _heritage.id,
        );
      } catch (_) {}
    }();

    await Future.wait([
      dataJob,
      _precacheFightAssets(),
      Future<void>.delayed(const Duration(milliseconds: 350)),
    ]);

    if (!mounted) return;
    context.replace(
      '/fight',
      extra: FightInitialData(state: state, groups: groups),
    );
  }

  Future<void> _precacheFightAssets() async {
    final paths = <String>[
      'assets/images/bg_fight.png',
      'assets/images/fight_map.png',
      'assets/images/supply_station.png',
      'assets/icons/buttons/my_heritages_btn.png',
      'assets/icons/buttons/supply_station_btn.png',
      'assets/icons/times_up.png',
      'assets/heritages/${_heritage.id}/fight.png',
      'assets/heritages/${_heritage.id}/main.png',
      'assets/heritages/${_heritage.id}/enemy.png',
      for (final c in componentsOf(_heritage.id)) c.imagePath,
    ];
    await Future.wait([
      for (final p in paths)
        precacheImage(AssetImage(p), context, onError: (_, _) {}),
    ]);
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: LoadingScreen());
}
