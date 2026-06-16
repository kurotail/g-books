import 'dart:io';
import 'api_client.dart';

/// 頭像上傳服務介面
///
/// Mock 實作直接回傳本地路徑（同裝置測試用）。
/// 串後端時換成 [ApiAvatarService]，其餘程式碼不用動。回傳值（本地路徑或後端相對 URL）
/// 統一由 [resolveMediaUrl] 在顯示端解析。
abstract class AvatarService {
  /// 上傳裁切後的本地圖片，回傳可供顯示 / 儲存的 URL；失敗回傳 null。
  Future<String?> upload(String localPath);
}

class MockAvatarService implements AvatarService {
  @override
  Future<String?> upload(String localPath) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return localPath; // mock：直接回傳本地路徑供同裝置預覽
  }
}

/// 後端實作：把本地裁切圖上傳到 `POST /api/image`，回傳後端服務該檔的相對 URL
/// （如 `/images/xxx.jpg`）。此值會存進使用者 / 小組的頭像欄位（`/api/users|group/pfp`），
/// 顯示時由 [resolveMediaUrl] 補成絕對網址。
class ApiAvatarService implements AvatarService {
  ApiAvatarService(this._client);

  final ApiClient _client;

  @override
  Future<String?> upload(String localPath) async {
    try {
      final bytes = await File(localPath).readAsBytes();
      final name = localPath.split(RegExp(r'[\\/]')).last;
      final url =
          await _client.uploadImage(bytes, name.isEmpty ? 'avatar.jpg' : name);
      return url.isEmpty ? null : url;
    } catch (_) {
      return null;
    }
  }
}
