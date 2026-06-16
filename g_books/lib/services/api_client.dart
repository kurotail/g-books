import 'dart:convert';
import 'dart:io';

/// 後端基底位址。
/// - Android 模擬器連本機後端：`http://10.0.2.2:8080`
/// - 實機平板：改成後端電腦的區網 IP（例：`http://192.168.0.10:8080`）
///
/// 可用 `--dart-define=GB_API_BASE=http://x.x.x.x:8080` 覆寫，不必改碼。
const String kApiBaseUrl = String.fromEnvironment(
  'GB_API_BASE',
  defaultValue: 'http://10.0.2.2:8080',
);

/// 後端回非 2xx 時拋出；[message] 為後端的純文字錯誤內容（後端以 `http.Error` 回傳純文字）。
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// 與 `gb_api` 往返的 HTTP client：持有 JWT、自動帶 access token，遇 401 會用
/// refresh token 換新後重試一次（refresh 為單次使用、後端每次輪換）。
///
/// 採 `dart:io` 的 [HttpClient]，無需額外套件；Android 專案可直接使用。
class ApiClient {
  ApiClient({String baseUrl = kApiBaseUrl}) : _baseUrl = baseUrl;

  final String _baseUrl;
  final HttpClient _http = HttpClient();

  String? _accessToken;
  String? _refreshToken;

  String get baseUrl => _baseUrl;
  String? get accessToken => _accessToken;
  bool get isLoggedIn => _accessToken != null;

  void setTokens({required String access, required String refresh}) {
    _accessToken = access;
    _refreshToken = refresh;
  }

  void clearTokens() {
    _accessToken = null;
    _refreshToken = null;
  }

  /// 登入：`POST /api/login`，成功後保存 token pair。失敗拋 [ApiException]（401=帳密錯誤）。
  Future<void> login(String username, String password) async {
    final raw = await _send(
      'POST',
      '/api/login',
      body: {'username': username, 'password': password},
      auth: false,
    );
    final m = jsonDecode(raw) as Map<String, dynamic>;
    setTokens(
      access: m['access_token'] as String,
      refresh: m['refresh_token'] as String,
    );
  }

  /// GET → 回傳已解析的 JSON（空 body → null）。
  Future<dynamic> getJson(String path, {Map<String, String>? query}) async {
    final raw = await _send('GET', path, query: query);
    return raw.isEmpty ? null : jsonDecode(raw);
  }

  /// POST / PUT / DELETE → 回傳已解析的 JSON（空 body → null）。
  Future<dynamic> sendJson(String method, String path, {Object? body}) async {
    final raw = await _send(method, path, body: body);
    return raw.isEmpty ? null : jsonDecode(raw);
  }

  /// 用目前 refresh token 換新 token pair；成功更新並回 true，失敗清除並回 false。
  Future<bool> _refresh() async {
    final rt = _refreshToken;
    if (rt == null) return false;
    try {
      final (status, text) =
          await _raw('POST', '/api/refresh', {'refresh_token': rt}, null, false);
      if (status < 200 || status >= 300) {
        clearTokens();
        return false;
      }
      final m = jsonDecode(text) as Map<String, dynamic>;
      setTokens(
        access: m['access_token'] as String,
        refresh: m['refresh_token'] as String,
      );
      return true;
    } catch (_) {
      clearTokens();
      return false;
    }
  }

  Future<String> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool auth = true,
  }) async {
    var (status, text) = await _raw(method, path, body, query, auth);
    // access token 過期（15 分鐘）→ 換新後重試一次。
    if (status == 401 && auth && await _refresh()) {
      (status, text) = await _raw(method, path, body, query, auth);
    }
    if (status < 200 || status >= 300) {
      throw ApiException(status, text.trim());
    }
    return text;
  }

  Future<(int, String)> _raw(
    String method,
    String path,
    Object? body,
    Map<String, String>? query,
    bool auth,
  ) async {
    final uri = Uri.parse('$_baseUrl$path')
        .replace(queryParameters: query == null || query.isEmpty ? null : query);
    final req = await _http.openUrl(method, uri);
    if (body != null) req.headers.contentType = ContentType.json;
    if (auth && _accessToken != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_accessToken');
    }
    if (body != null) req.add(utf8.encode(jsonEncode(body)));
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    return (resp.statusCode, text);
  }

  void dispose() => _http.close(force: true);
}
