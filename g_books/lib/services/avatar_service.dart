/// 頭像上傳服務介面
///
/// Mock 實作直接回傳本地路徑（同裝置測試用）。
/// 串後端時只需換成真實實作，其餘程式碼不用動。
abstract class AvatarService {
  /// 上傳裁切後的本地圖片，回傳遠端 URL；失敗回傳 null。
  Future<String?> upload(String localPath);
}

class MockAvatarService implements AvatarService {
  @override
  Future<String?> upload(String localPath) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return localPath; // mock：直接回傳本地路徑供同裝置預覽
  }
}
