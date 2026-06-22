import 'dart:convert';
import 'dart:io';

/// 後端基底位址。
/// - Android 模擬器直連本機後端（go run，:8080）：`http://10.0.2.2:8080`（預設）
/// - 實機平板直連：改成後端電腦的區網 IP（例：`http://192.168.0.10:8080`）
/// - Docker Compose 部署（nginx 邊緣終結 HTTPS、8080 不對外）：改用
///   `https://<主機或區網IP>`（443）。憑證為自簽，本 client 已放行自簽憑證（見下）。
///
/// 可用 `--dart-define=GB_API_BASE=https://192.168.0.10` 覆寫，不必改碼。
const String kApiBaseUrl = String.fromEnvironment(
  'GB_API_BASE',
  defaultValue: 'https://10.0.2.2',
  // defaultValue: 'https://192.168.207.10',
);

/// 把後端媒體路徑（上傳後端回的 `/images/..` 或 `/audio/..` 相對路徑）補成可載入的絕對
/// URL；已是 http(s) 絕對網址、本地檔路徑或 null 則原樣回傳。供頭像等顯示解析用。
/// 後端 reads 不走 API（Docker 由 nginx 直接服務 `/images/`、`/audio/`），故以 baseUrl
/// 補前綴；直跑 go（無 nginx）時這些路徑不會被服務，顯示端應有載入失敗的後備。
String? resolveMediaUrl(String? raw) {
  if (raw == null || raw.isEmpty) return raw;
  if (raw.startsWith('/images/') || raw.startsWith('/audio/')) {
    return '$kApiBaseUrl$raw';
  }
  return raw;
}

/// 讓 Flutter 預設網路堆疊（不經 [ApiClient] 的連線，主要是 [Image.network] 載入頭像
/// `/images/..`）也能連上後端 nginx 的「自簽 HTTPS」。
///
/// [ApiClient] 只在自己的 [HttpClient] 放行自簽憑證，但頭像圖片由框架的預設 client 載入、
/// 仍會驗證憑證 → 自簽會被拒，造成「上傳成功（走 ApiClient）卻不顯示頭像（走 Image.network）」。
/// 在 `main()` 以 `HttpOverrides.global = BackendHttpOverrides();` 安裝即可解。
///
/// 只對後端主機（[kApiBaseUrl] 的 host）放行，其餘主機維持預設憑證驗證（信任範圍與
/// [ApiClient] 一致；區網教學情境可接受，正式環境應改用受信任憑證）。
class BackendHttpOverrides extends HttpOverrides {
  BackendHttpOverrides() : _host = Uri.parse(kApiBaseUrl).host;

  final String _host;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => host == _host;
  }
}

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
  ApiClient({String baseUrl = kApiBaseUrl}) : _baseUrl = baseUrl {
    // 後端 Docker 部署以 nginx 自簽憑證終結 HTTPS（見 gb_api/README）。dart:io 預設會
    // 拒絕自簽憑證，使所有 https/wss 連線失敗；此處放行憑證錯誤，讓自簽 https 後端可用。
    // 範圍僅本 client 連到所設定的後端位址；純 http 連線不觸發此 callback、不受影響。
    // 注意：等同信任該位址的任何憑證（區網教學情境可接受）；正式環境應改用受信任憑證
    // 或內嵌後端憑證做 pinning。
    _http.badCertificateCallback = (cert, host, port) => true;
  }

  final String _baseUrl;
  final HttpClient _http = HttpClient();

  String? _accessToken;
  String? _refreshToken;

  String get baseUrl => _baseUrl;

  /// 供狀態 WebSocket 共用同一個 [HttpClient]（含自簽憑證放行），讓 `wss://` 自簽後端
  /// 的握手不被拒。見 [ApiGameStateService]。
  HttpClient get httpClient => _http;
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

  /// 上傳圖片到 `POST /api/image`（multipart/form-data，欄位名 `file`）。回傳後端服務該
  /// 檔的相對 URL（如 `/images/xxx.jpg`，存進 building/頭像時即用此值）。401 會換 token
  /// 重試一次；非 2xx 拋 [ApiException]。
  Future<String> uploadImage(List<int> bytes, String filename) =>
      _uploadMedia('/api/image', bytes, filename);

  /// 上傳音檔到 `POST /api/audio`（語音題敘述 / 語音選項 / 語音作答參考）。回傳該檔的相對
  /// URL（如 `/audio/xxx.mp3`）。與 [uploadImage] 同走 multipart 欄位 `file`、共用 401 重試。
  Future<String> uploadAudio(List<int> bytes, String filename) =>
      _uploadMedia('/api/audio', bytes, filename);

  /// 把錄音轉文字：`POST /api/stt`（教師/管理者限定；學生會收到 403）。傳入音檔位元組
  /// （後端要求 WAV），內部 base64 編碼後送出，回傳辨識文字。供題庫匯入時把「語音作答題
  /// 的參考音檔」轉成可比對的答案文字。STT 在 CPU 上可能偏慢，呼叫端需容忍較長等待。
  /// 401 會換 token 重試一次；非 2xx（含 500：STT 服務不可用）拋 [ApiException]。
  Future<String> transcribeAudio(List<int> bytes) async {
    final raw = await _send(
      'POST',
      '/api/stt',
      body: {'audio_b64': base64Encode(bytes)},
    );
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return (m['text'] as String?) ?? '';
  }

  Future<String> _uploadMedia(
    String path,
    List<int> bytes,
    String filename,
  ) async {
    var (status, text) = await _rawMultipart(path, bytes, filename);
    if (status == 401 && await _refresh()) {
      (status, text) = await _rawMultipart(path, bytes, filename);
    }
    if (status < 200 || status >= 300) {
      throw ApiException(status, text.trim());
    }
    final m = jsonDecode(text) as Map<String, dynamic>;
    return (m['url'] as String?) ?? '';
  }

  Future<(int, String)> _rawMultipart(
    String path,
    List<int> bytes,
    String filename,
  ) async {
    final uri = Uri.parse('$_baseUrl$path');
    final req = await _http.openUrl('POST', uri);
    final boundary = '----gbooks${DateTime.now().microsecondsSinceEpoch}';
    req.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );
    if (_accessToken != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_accessToken');
    }
    // 後端以「內容嗅探」決定型別，故 part 的 Content-Type 用 octet-stream 即可。
    req.add(
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="$filename"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n',
      ),
    );
    req.add(bytes);
    req.add(utf8.encode('\r\n--$boundary--\r\n'));
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    return (resp.statusCode, text);
  }

  /// 用目前 refresh token 換新 token pair；成功更新並回 true，失敗清除並回 false。
  Future<bool> _refresh() async {
    final rt = _refreshToken;
    if (rt == null) return false;
    try {
      final (status, text) = await _raw(
        'POST',
        '/api/refresh',
        {'refresh_token': rt},
        null,
        false,
      );
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
    final uri = Uri.parse(
      '$_baseUrl$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
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
