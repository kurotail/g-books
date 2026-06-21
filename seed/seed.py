#!/usr/bin/env python3
"""把北港朝天宮古蹟設定種進 gb_api。

  1. 用預設管理員帳號打 POST /api/login 取得 JWT
  2. 讀 building_beigang.json，把可讀的巢狀 layout 物件壓成「JSON 字串」
     （後端把 layout 當不透明字串原樣保存，故此欄必須是字串）
  3. 若已有同名 building → PUT 覆蓋，否則 POST 新建

用法：
  python seed.py          # 要改後端位址或帳密，改下方常數即可
"""
import json
import os
import ssl
import urllib.error
import urllib.request

# ── 設定（要改就改這裡）─────────────────────────────────────────────
BASE_URL = "https://localhost:443"  # 後端位址（Docker/nginx HTTPS）；直跑 go 改 http://localhost:8080
ADMIN_USER = "admin"                # 預設管理員帳號
ADMIN_PASS = "admin123"             # 預設管理員密碼
# ────────────────────────────────────────────────────────────────

HERITAGE_ID = "beigang_chaotian_temple"
DATA_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "building_beigang.json")

# 放行自簽憑證（Docker/nginx HTTPS）；對 http 無影響。
_SSL = ssl.create_default_context()
_SSL.check_hostname = False
_SSL.verify_mode = ssl.CERT_NONE


def request(method, url, token=None, body=None):
    data = None
    headers = {}
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json; charset=utf-8"
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, context=_SSL) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw) if raw.strip() else None


def main():
    base = BASE_URL.rstrip("/")

    with open(DATA_PATH, encoding="utf-8") as f:
        data = json.load(f)
    # layout 由巢狀物件壓成字串（後端原樣保存）。
    data["layout"] = json.dumps(data["layout"], ensure_ascii=False, separators=(",", ":"))

    print(f"==> 登入 {base} (使用者 {ADMIN_USER})")
    try:
        login = request("POST", f"{base}/api/login",
                        body={"username": ADMIN_USER, "password": ADMIN_PASS})
    except urllib.error.HTTPError as e:
        raise SystemExit(f"!! 登入失敗 HTTP {e.code}：{e.read().decode('utf-8', 'replace')}")
    token = (login or {}).get("access_token")
    if not token:
        raise SystemExit("!! 未取得 access_token")
    print("==> 取得 JWT")

    # 找有沒有同名 building（決定 PUT 覆蓋還是 POST 新建）。
    buildings = request("GET", f"{base}/api/building", token=token) or []
    existing = next((b for b in buildings if b.get("name") == HERITAGE_ID), None)

    try:
        if existing:
            bid = existing["building_id"]
            print(f"==> 已存在 building_id={bid} → PUT 覆蓋")
            res = request("PUT", f"{base}/api/building/{bid}", token=token, body=data)
        else:
            print("==> 尚無同名 building → POST 新建")
            res = request("POST", f"{base}/api/building", token=token, body=data)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"!! 寫入 building 失敗 HTTP {e.code}：{e.read().decode('utf-8', 'replace')}")

    print(json.dumps(res, ensure_ascii=False, indent=2))
    print("==> 完成")


if __name__ == "__main__":
    main()
