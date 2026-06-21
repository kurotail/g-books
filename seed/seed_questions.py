#!/usr/bin/env python3
"""把 seed/quest/quest.csv 的題庫種進 gb_api（POST /api/question/upload）。

流程：
  1. 用管理員帳號 POST /api/login 取得 JWT
  2. 讀 quest/quest.csv（欄位：題目,A,B,C,D,答案,難度；第一列為欄名，允許 BOM）
  3. 逐列判斷題型，需要時把 quest/audio/ 下的音檔以 POST /api/audio 上傳取得 URL
  4. 依「各難度 75% 採集(area 1) / 25% 攻防戰(area 2)」分配 area
  5. 整批 POST /api/question/upload，印出每題結果（後端回 207 Multi-Status）

答案可有多個正解（後端 answer.data 為「非空陣列」，學生只需答對其一）；同一格用 | 分隔。

題型判斷（同 App 內 ZIP 匯入器的規則）：
  - 題目欄是音檔路徑   → 語音敘述題（description.type=audio，data=音檔 URL）
  - A~D 皆空           → 語音作答題（answer.type=voice_response，data=辨識文字陣列）
                         答案欄的 token 若是音檔 → 先呼叫本機 STT 服務（/transcribe）轉成
                         文字再存；若是文字 → 直接當辨識答案。後端以 STT 轉文字後比對評分。
  - A~D 有值           → 選擇題（answer.type=index，data=索引陣列）；答案欄為一或多個
                         字母（如 A 或 A|C）。任一選項是音檔 → 把音檔 URL 當選項字串存
                         （後端選項型別仍是 text；學生端 UI 需把 /audio/ 選項渲染成播放鈕）

前置：語音作答題若以參考音檔當答案，需先啟動 taigi_stt 服務（見 taigi_stt/README.md，
      預設 http://localhost:8964）。服務未開時，該類題會被略過（其餘照常上傳）。

用法：
  python seed_questions.py        # 要改後端位址或帳密、難度→area 比例、STT 位址，改下方常數
"""
import base64
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
STT_BASE_URL = "http://localhost:8964"  # 本機 Taigi STT 服務（轉語音作答題的參考音檔）
# ────────────────────────────────────────────────────────────────

HERE = os.path.dirname(os.path.abspath(__file__))
# quest.csv 與 audio/ 同住 quest/；CSV 內音檔路徑（如 audio/q1.wav）相對於此資料夾。
QUEST_DIR = os.path.join(HERE, "quest")
CSV_PATH = os.path.join(QUEST_DIR, "quest.csv")

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
    """把 quest/ 下被引用的音檔（題目敘述 / 選項）上傳到 POST /api/audio，回傳 /audio/.. URL；
    同檔只傳一次。CSV 內的相對路徑（如 audio/x.wav）相對於 QUEST_DIR 解析。"""

    def __init__(self, base, token):
        self._base = base
        self._token = token
        self._cache = {}

    def url_for(self, rel_path):
        rel_path = rel_path.strip().replace("\\", "/")
        if rel_path in self._cache:
            return self._cache[rel_path]
        src = os.path.join(QUEST_DIR, *rel_path.split("/"))
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


class STTClient:
    """把語音作答題的參考音檔丟給本機 Taigi STT（POST {base}/transcribe）轉成文字；
    回傳的文字即「可接受的標準答案」（後端評分時也用同一模型轉學生錄音再比對）。
    同檔只轉一次。失敗（服務未開 / 回空字串）丟 ValueError，由呼叫端略過該列。"""

    def __init__(self, base):
        self._base = base.rstrip("/")
        self._cache = {}

    def text_for(self, rel_path):
        rel_path = rel_path.strip().replace("\\", "/")
        if rel_path in self._cache:
            return self._cache[rel_path]
        src = os.path.join(QUEST_DIR, *rel_path.split("/"))
        if not os.path.isfile(src):
            raise ValueError(f"找不到參考音檔：{rel_path}")
        with open(src, "rb") as f:
            audio_b64 = base64.b64encode(f.read()).decode()
        body = json.dumps({"audio_b64": audio_b64}).encode("utf-8")
        req = urllib.request.Request(self._base + "/transcribe", data=body, method="POST")
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                text = (json.loads(resp.read().decode("utf-8")).get("text") or "").strip()
        except urllib.error.HTTPError as e:
            raise ValueError(f"STT 轉檔失敗 HTTP {e.code}：{e.read().decode('utf-8', 'replace')}")
        except urllib.error.URLError as e:
            raise ValueError(f"STT 服務連線失敗（{self._base}，是否已啟動？）：{e.reason}")
        if not text:
            raise ValueError(f"STT 對 {rel_path} 回傳空字串")
        self._cache[rel_path] = text
        print(f"    🗣 STT {rel_path} → 「{text}」")
        return text


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


def build_question(row, audio, stt):
    """把一列轉成 QuestionInput（content/answer/difficulty/area）。回傳 (payload, kind)。

    答案欄以 | 分隔多個正解；answer.data 一律為陣列（選擇題=索引、語音題=辨識文字）。"""
    prompt, options, ans = row["prompt"], row["options"], row["answer"]

    # 敘述：音檔路徑 → audio，否則 text。
    if is_audio(prompt):
        description = {"type": "audio", "data": audio.url_for(prompt)}
    else:
        description = {"type": "text", "data": prompt}

    nonempty = [(L, v) for L, v in zip(LETTERS, options) if v]
    tokens = [t.strip() for t in ans.split("|") if t.strip()]

    if not nonempty:
        # 語音作答題：每個 token 若是音檔 → 用 STT 轉文字；是文字 → 直接採用。
        if not tokens:
            raise ValueError("語音作答題（無選項）缺少答案")
        texts = [stt.text_for(t) if is_audio(t) else t for t in tokens]
        answer = {"type": "voice_response", "data": texts}
        content = {"description": description}  # 無 choices
        kind = "voice"
    else:
        # 選擇題：答案是一或多個字母。選項若為音檔則上傳並以 URL 當選項字串。
        if not tokens:
            raise ValueError("選擇題缺少答案")
        labels = [L for L, _ in nonempty]
        idxs = []
        for t in tokens:
            tu = t.upper()
            if tu not in labels:
                raise ValueError(f"答案「{t}」不在現有選項 {labels} 中")
            i = labels.index(tu)
            if i not in idxs:
                idxs.append(i)
        choices_data = [audio.url_for(v) if is_audio(v) else v for _, v in nonempty]
        content = {"description": description, "choices": {"type": "text", "data": choices_data}}
        answer = {"type": "index", "data": idxs}
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
    stt = STTClient(STT_BASE_URL)
    questions, kinds, skipped = [], [], 0
    for row in parsed:
        try:
            payload, kind = build_question(row, audio, stt)
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
    if skipped:
        print(f"==> 注意：略過 {skipped} 題（含 STT 未啟動 / 答案格式不符；見上方逐列訊息）。")


if __name__ == "__main__":
    main()
