import 'models/heritage_model.dart';

/// Index of the teacher-assigned heritage in [mockHeritages].
/// Replace with server-fetched data when API is ready.
const int kInitialHeritageIndex = 1;

final List<HeritageModel> mockHeritages = [
  const HeritageModel(
    id: 'anping_old_fort',
    name: '安平古堡',
    subtitle: '',
    description:
        '安平古堡位於台南市安平區，建於西元1624年荷蘭統治時期，原名「熱蘭遮城」，'
        '是台灣第一座西式稜堡，也是當時荷蘭東印度公司在台的統治核心。\n\n'
        '1661年，鄭成功率軍渡海攻台，圍城九個月後荷蘭人出降。鄭氏將此地改稱「王城」，'
        '成為明鄭時期的行政中心。清朝統治台灣後，城牆因疏於維護而逐漸荒廢，磚石常被拆去作為其他工程建材。'
        '日治時期，日人利用舊城牆基座修建海關宿舍，這才奠定了今日我們所見的遺跡樣貌。\n\n'
        '現存高台上的白色瞭望台為日治時期後人重建，登上可眺望台江舊址與安平港灣。'
        '城內的展示館詳述了荷、鄭、清朝四百年來的台灣海洋貿易史，是認識台灣近代史的重要起點。',
    cardImagePath: 'assets/images/heritages/heritage_cards/anping_old_fort.png',
    status: HeritageStatus.locked,
  ),
  const HeritageModel(
    id: 'beigang_chaotian_temple',
    name: '北港朝天宮',
    subtitle: '從信仰的起點，展開你的征途',
    description:
        '北港朝天宮位於雲林縣北港鎮，建於清康熙三十三年（西元1694年），'
        '是台灣最具代表性與歷史價值的媽祖廟之一，每年吸引數百萬名信眾與觀光客前來參拜。\n\n'
        '廟宇建築融合了閩南傳統建築風格，屋頂結構精雕細琢，並大量運用剪黏、交趾陶等傳統工藝裝飾，'
        '整體格局金碧輝煌、氣勢雄偉，完美彰顯了台灣傳統工藝與寺廟建築之美。\n\n'
        '每年農曆三月的「北港媽祖遶境」活動，已被列為台灣國家重要無形文化資產。'
        '遶境期間鑼鼓喧天、藝閣遊行，吸引全台信眾共同參與，是感受台灣民間信仰文化氛圍的最佳場合。',
    cardImagePath:
        'assets/images/heritages/heritage_cards/beigang_chaotian_temple.png',
    status: HeritageStatus.assigned,
  ),
  const HeritageModel(
    id: 'chihkan_tower',
    name: '赤崁樓',
    subtitle: '',
    description:
        '赤崁樓位於台南市中西區，建於西元1653年荷蘭統治時期，'
        '原名「普羅民遮城」，是荷蘭人設立的地方行政機關，'
        '與安平的熱蘭遮城共同構成荷治台灣的雙城格局。\n\n'
        '1661年鄭成功攻台，首先攻下普羅民遮城，此地隨即成為明鄭時期的行政重心。'
        '清代改建後，原有的荷式城堡主體逐漸融入漢式廟宇格局。現存的文昌閣與海神廟為清末重建，'
        '與留存的荷式紅磚城垣基座並存，形成了獨特且具層次感的歷史疊層。\n\n'
        '庭園中九隻石龜馱著的御碑，記載了清乾隆皇帝褒獎平定林爽文事件的詔文，'
        '是台灣現存最具代表性的清代御碑群。赤崁樓橫跨荷、鄭、清三朝，是台南城市發展不可或缺的歷史座標。',
    cardImagePath: 'assets/images/heritages/heritage_cards/chihkan_tower.png',
    status: HeritageStatus.locked,
  ),
  const HeritageModel(
    id: 'former_british_consular_residence',
    name: '前清英國領事官邸',
    subtitle: '',
    description:
        '前清英國領事官邸位於新北市淡水區，'
        '座落於紅毛城主堡東側，落成於西元1891年，是英國在台灣所建造的第三座領事官邸，現為國定古蹟。\n\n'
        '建築由英國建築師設計、中國工匠施工，採用紅磚拱廊結合閩南式紅瓦屋頂，一樓使用弧形拱，二樓則為半圓拱，'
        '是極具特色的英國「殖民地樣式建築」。官邸欄杆更點綴了象徵平安的綠釉花瓶，完美融合東西方的建築美學。\n\n'
        '此處居高臨下，可遠眺淡水河口與觀音山的落日美景。內部完好保存了維多利亞時代的客廳、餐廳與壁爐配置，'
        '與鄰近的紅毛城主堡共同見證了台灣近代開港通商、涉外外交與長達數百年的歷史變遷。',
    cardImagePath:
        'assets/images/heritages/heritage_cards/former_british_consular_residence.png',
    status: HeritageStatus.locked,
  ),
];
