#!/usr/bin/env python3
"""把 seed/quest/quest.csv 的題庫種進 gb_api（POST /api/question/upload）。

流程：
  1. 用管理員帳號 POST /api/login 取得 JWT
  2. 讀 quest/quest.csv（欄位：題目,A,B,C,D,答案,難度；第一列為欄名，允許 BOM）
  3. 逐列判斷題型，需要時把 quest/audio/ 下的音檔以 POST /api/audio 上傳取得 URL
  4. 依「各難度 75% 採集(area 1) / 25% 攻防戰(area 2)」分配 area
  5. 整批 POST /api/question/upload，印出每題結果（後端回 207 Multi-Status）

題型判斷（同 App 內 ZIP 匯入器的規則）：
  - 題目欄是音檔路徑     → 語音敘述題（description.type=audio，data=音檔 URL）
  - A~D 皆空、答案是音檔 → 語音作答題（answer.type=voice_response）
                           ⚠️ 後端目前以「STT 文字 vs 儲存的文字」評分，這裡答案是
                              參考音檔 URL，需後端支援「對參考音檔評分」才會自動判對，
                              詳見 README 的待後端需求。匯入本身可成功。
  - A~D 有值、答案是 ABCD → 選擇題（answer.type=index）
        其中任一選項是音檔   → 把音檔 URL 當成選項字串存（後端選項型別仍是 text，
                              不需改後端；學生端 UI 需另外把 /audio/ 選項渲染成播放鈕）

用法：
  python seed_questions.py        # 要改後端位址或帳密、難度→area 比例，改下方常數即可
"""
import csv
import json
import os
import ssl
import urllib.error
import urllib.request
from collections import defaultdict

# ── 設定（要改就改這裡）─────────────────────────────────────────────
BASE_URL = "https://localhost:443"  # 後端位址（Docker/nginx HTTPS）；直跑 go 改 http://localhost:8080
ADMIN_USER = "admin"                # 需 role>=教師 才能上傳題目
ADMIN_PASS = "admin123"
QUIZ2_RATIO = 0.25                  # 各難度分到攻防戰(area 2)的比例，其餘進採集(area 1)
# ────────────────────────────────────────────────────────────────

HERE = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(HERE, "quest", "quest.csv")
AUDIO_DIR = os.path.join(HERE, "quest", "audio")

AREA_COLLECT = 1  # 採集 / 平時（NORMAL・QUIZ1）
AREA_FIGHT = 2    # 攻防戰（QUIZ2）

# 後端 media 服務接受的音檔副檔名（見 gb_api internal/service/media.go）。
AUDIO_EXTS = {".mp3", ".wav", ".ogg", ".m4a", ".aac", ".flac", ".aiff"}
LETTERS = ["A", "B", "C", "D"]

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


def is_audio(value):
    """欄位值是否為音檔路徑（依副檔名判斷）。"""
    return bool(value) and os.path.splitext(value)[1].lower() in AUDIO_EXTS


class AudioUploader:
    """把 quest/audio/ 下的音檔上傳到 POST /api/audio，回傳 /audio/.. URL；同檔只傳一次。"""

    def __init__(self, base, token):
        self._base = base
        self._token = token
        self._cache = {}

    def url_for(self, rel_path):
        rel_path = rel_path.strip().replace("\\", "/")
        if rel_path in self._cache:
            return self._cache[rel_path]
        src = os.path.join(AUDIO_DIR, *rel_path.split("/"))
        if not os.path.isfile(src):
            raise SystemExit(f"!! 找不到音檔：{src}（quest.csv 指到 {rel_path}）")
        url = self._upload(src)
        self._cache[rel_path] = url
        print(f"    ↑ 上傳音檔 {rel_path} → {url}")
        return url

    def _upload(self, src):
        with open(src, "rb") as f:
            data = f.read()
        boundary = "----gbseed" + os.urandom(8).hex()
        filename = os.path.basename(src)
        body = b"".join([
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode(),
            b"Content-Type: application/octet-stream\r\n\r\n",
            data,
            f"\r\n--{boundary}--\r\n".encode(),
        ])
        req = urllib.request.Request(self._base + "/api/audio", data=body, method="POST")
        req.add_header("Content-Type", "multipart/form-data; boundary=" + boundary)
        req.add_header("Authorization", "Bearer " + self._token)
        try:
            with urllib.request.urlopen(req, context=_SSL) as resp:
                return json.loads(resp.read().decode("utf-8"))["url"]
        except urllib.error.HTTPError as e:
            raise SystemExit(f"!! 音檔上傳失敗 HTTP {e.code}：{e.read().decode('utf-8', 'replace')}")


def parse_rows():
    """讀 quest.csv → [{prompt, options[4], answer, difficulty, line}]，跳過格式不符的列。"""
    with open(CSV_PATH, encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        rows = [[(c or "").strip() for c in r] for r in reader if any((c or "").strip() for c in r)]
    if not rows:
        raise SystemExit(f"!! {CSV_PATH} 沒有資料")

    parsed = []
    for line_no, r in enumerate(rows[1:], start=2):  # 跳過第一列欄名
        r = (r + [""] * 7)[:7]
        prompt, a, b, c, d, ans, diff = r
        if not prompt:
            print(f"  - 第 {line_no} 列：題目為空，略過")
            continue
        if not diff.isdigit():
            print(f"  - 第 {line_no} 列：難度「{diff}」非數字，略過")
            continue
        parsed.append({
            "prompt": prompt,
            "options": [a, b, c, d],
            "answer": ans,
            "difficulty": int(diff),
            "line": line_no,
        })
    return parsed


def assign_areas(parsed):
    """依各難度把 QUIZ2_RATIO 比例的題目（均勻散布）標成 area 2，其餘 area 1。"""
    by_diff = defaultdict(list)
    for i, row in enumerate(parsed):
        by_diff[row["difficulty"]].append(i)
    for diff, idxs in sorted(by_diff.items()):
        n = len(idxs)
        k = int(n * QUIZ2_RATIO + 0.5)  # 四捨五入(.5 進位)，與 App 端 Dart .round() 一致
        fight_positions = {int((j + 0.5) * n / k) for j in range(k)} if k else set()
        for pos, i in enumerate(idxs):
            parsed[i]["area"] = AREA_FIGHT if pos in fight_positions else AREA_COLLECT
        print(f"  難度 {diff}：{n} 題 → 採集 {n - len(fight_positions)} / 攻防戰 {len(fight_positions)}")


def build_question(row, audio):
    """把一列轉成 QuestionInput（content/answer/difficulty/area）。回傳 (payload, kind)。"""
    prompt, options, ans = row["prompt"], row["options"], row["answer"]

    # 敘述：音檔路徑 → audio，否則 text。
    if is_audio(prompt):
        description = {"type": "audio", "data": audio.url_for(prompt)}
    else:
        description = {"type": "text", "data": prompt}

    nonempty = [(L, v) for L, v in zip(LETTERS, options) if v]

    if not nonempty:
        # 語音作答題：答案是參考音檔（⚠️ 待後端支援對音檔評分）。
        if not is_audio(ans):
            raise ValueError("無選項且答案不是音檔，無法判斷題型")
        answer = {"type": "voice_response", "data": audio.url_for(ans)}
        content = {"description": description}  # 無 choices
        kind = "voice"
    else:
        # 選擇題：答案是 ABCD。選項若為音檔則上傳並以 URL 當選項字串。
        ans = ans.upper()
        labels = [L for L, _ in nonempty]
        if ans not in labels:
            raise ValueError(f"答案「{row['answer']}」不在現有選項 {labels} 中")
        choices_data = [audio.url_for(v) if is_audio(v) else v for _, v in nonempty]
        content = {"description": description, "choices": {"type": "text", "data": choices_data}}
        answer = {"type": "index", "data": labels.index(ans)}
        kind = "audio_choice" if any(is_audio(v) for _, v in nonempty) else "text_mc"

    payload = {
        "content": content,
        "answer": answer,
        "difficulty": row["difficulty"],
        "area": row["area"],
    }
    return payload, kind


def main():
    base = BASE_URL.rstrip("/")

    print(f"==> 讀題庫 {CSV_PATH}")
    parsed = parse_rows()
    print(f"==> 共 {len(parsed)} 題，分配 area（攻防戰比例 {QUIZ2_RATIO:.0%}）")
    assign_areas(parsed)

    print(f"==> 登入 {base}（使用者 {ADMIN_USER}）")
    try:
        login = request("POST", f"{base}/api/login",
                        body={"username": ADMIN_USER, "password": ADMIN_PASS})
    except urllib.error.HTTPError as e:
        raise SystemExit(f"!! 登入失敗 HTTP {e.code}：{e.read().decode('utf-8', 'replace')}")
    token = (login or {}).get("access_token")
    if not token:
        raise SystemExit("!! 未取得 access_token")
    print("==> 取得 JWT")

    audio = AudioUploader(base, token)
    questions, kinds, skipped = [], [], 0
    for row in parsed:
        try:
            payload, kind = build_question(row, audio)
        except ValueError as e:
            print(f"  - 第 {row['line']} 列略過：{e}")
            skipped += 1
            continue
        questions.append(payload)
        kinds.append(kind)

    if not questions:
        raise SystemExit("!! 沒有可上傳的題目")

    counts = defaultdict(int)
    for k in kinds:
        counts[k] += 1
    print(f"==> 題型統計：{dict(counts)}（略過 {skipped}）")

    print(f"==> 上傳 {len(questions)} 題 → POST /api/question/upload")
    try:
        res = request("POST", f"{base}/api/question/upload", token=token,
                      body={"questions": questions})
    except urllib.error.HTTPError as e:
        raise SystemExit(f"!! 上傳失敗 HTTP {e.code}：{e.read().decode('utf-8', 'replace')}")

    results = (res or {}).get("results", [])
    created = sum(1 for r in results if r.get("status") == 201)
    print(f"==> 完成：成功 {created} / {len(results)}")
    for r in results:
        if r.get("status") != 201:
            print(f"  !! 第 {r.get('index')} 題失敗（{r.get('status')}）：{r.get('error')}")
    if any(k == "voice" for k in kinds):
        print("==> 注意：語音作答題已匯入，但後端目前以文字評分，"
              "需補『對參考音檔評分』才會自動判對（見待後端需求）。")


if __name__ == "__main__":
    main()
