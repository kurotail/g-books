/// 是否串接真實後端（gb_api）。
///
/// 先預設 `false`（用本機 mock，App 可離線開發）；等後端把「各組學生帳號（username=
/// 姓名+座號、password=座號）＋ building 設定（Layout / item_allowed_slot /
/// difficulty_type）」備妥後，改成 `true` 即整組切換到後端，UI 不需更動。
///
/// 也可用 `--dart-define=GB_USE_BACKEND=false` 在不改碼的情況下切回 mock 離線開發。
const bool kUseBackend = bool.fromEnvironment(
  'GB_USE_BACKEND',
  defaultValue: true,
);
