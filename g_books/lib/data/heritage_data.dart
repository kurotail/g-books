import 'models/heritage_model.dart';

/// 老師指派的古蹟在 [mockHeritages] 的索引；之後改由後端回傳。
const int kInitialHeritageIndex = 1;

/// 古蹟的詳細圖文介紹改由 `assets/heritages/<id>/info.md` 提供（InfoDialog 呈現）。
final List<HeritageModel> mockHeritages = [
  const HeritageModel(
    id: 'anping_old_fort',
    name: '安平古堡',
    cardImagePath: 'assets/heritages/anping_old_fort/card.png',
    status: HeritageStatus.locked,
  ),
  const HeritageModel(
    id: 'beigang_chaotian_temple',
    name: '北港朝天宮',
    cardImagePath: 'assets/heritages/beigang_chaotian_temple/card.png',
    status: HeritageStatus.assigned,
  ),
  const HeritageModel(
    id: 'chihkan_tower',
    name: '赤崁樓',
    cardImagePath: 'assets/heritages/chihkan_tower/card.png',
    status: HeritageStatus.locked,
  ),
  const HeritageModel(
    id: 'former_british_consular_residence',
    name: '前清英國領事官邸',
    cardImagePath: 'assets/heritages/former_british_consular_residence/card.png',
    status: HeritageStatus.locked,
  ),
];
