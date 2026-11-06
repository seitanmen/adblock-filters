#!/usr/bin/env bash
# =============================================================================
#  publish.sh — adblock フィルタを Gist へ公開 + 検証
#
#  使い方:
#    ./publish.sh            # ローカルのファイルを Gist に反映し、取得して検証
#    ./publish.sh --check    # 検証のみ（公開しない）
#
#  トークンの取得順:
#    1) 環境変数 GH_TOKEN
#    2) macOS キーチェーン（推奨）: security find-generic-password -s gh-gist-token -w
#
#  トークンをキーチェーンへ登録する:
#    security add-generic-password -a "$USER" -s gh-gist-token -w 'ghp_xxxxx' -U
# =============================================================================
set -euo pipefail

GIST_ID="${GIST_ID:-ddee9b5f01fa9c4adaeca866ee9192c8}"
KEYCHAIN_SVC="${KEYCHAIN_SVC:-gh-gist-token}"
GIST_OWNER="${GIST_OWNER:-seitanmen}"
DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

FILES=(latest.txt adblock-generic.txt gamewith-adguard-filter.txt gamewith-safari-content-blocker.json README.md)

# --- token ---------------------------------------------------------------
TOKEN="${GH_TOKEN:-}"
if [ -z "$TOKEN" ] && command -v security >/dev/null 2>&1; then
  TOKEN="$(security find-generic-password -s "$KEYCHAIN_SVC" -w 2>/dev/null || true)"
fi
if [ -z "$TOKEN" ]; then
  cat >&2 <<'EOF'
ERROR: GitHub token が見つかりません。

  推奨（macOS キーチェーン・平文がディスクに残りません）:
    security add-generic-password -a "$USER" -s gh-gist-token -w 'ghp_xxxxx' -U

  簡易版（平文・ ~/.zshenv は非対話 zsh でも読まれます）:
    echo "export GH_TOKEN='ghp_xxxxx'" >> ~/.zshenv && chmod 600 ~/.zshenv
EOF
  exit 1
fi

# --- lint（構文チェック） -------------------------------------------------
python3 - "$DIR" <<'PY'
import re, sys, os
d = sys.argv[1]
problems = []
for name in ['latest.txt', 'adblock-generic.txt', 'gamewith-adguard-filter.txt']:
    p = os.path.join(d, name)
    if not os.path.exists(p):
        continue
    for i, line in enumerate(open(p, encoding='utf-8'), 1):
        t = line.strip()
        if not t or t.startswith('!'):
            continue
        if '#%#' in t:
            head = t.split('#%#')[0]
            if ',' not in head and '|' in head:
                problems.append(f'{name}:{i} scriptlet rule のドメインが | 区切り（カンマ必須）')
            if head.startswith('//') and ',' in head:
                problems.append(f'{name}:{i} scriptlet rule が //scriptlet をドメイン付き_destで使っています')
        elif '$$' in t:
            head = t.split('$$')[0]
            if ',' not in head and '|' in head:
                problems.append(f'{name}:{i} html-filter rule のドメインが | 区切り（カンマ必須）')
        elif '##' not in t and not re.search(r'\|\||\|http|://|\^', t):
            problems.append(f'{name}:{i} 分類できないルール: {t[:60]}')
if problems:
    print('LINT FAILED:')
    for p in problems:
        print('  -', p)
    sys.exit(1)
print('lint: OK')
PY

# --- publish -------------------------------------------------------------
if [ "$CHECK_ONLY" -eq 0 ]; then
  python3 - "$DIR" "$FILES" <<'PY' > /tmp/gw_publish_payload.json
import json, os, sys
d, files = sys.argv[1], sys.argv[2].split(',')
out = {}
for name in files:
    src = 'README-gist.md' if name == 'README.md' else name
    out[name] = {'content': open(os.path.join(d, src), encoding='utf-8').read()}
print(json.dumps({'files': out}, ensure_ascii=False))
PY
  CODE=$(curl -sS -o /tmp/gw_publish_resp.json -w "%{http_code}" -X PATCH \
    "https://api.github.com/gists/${GIST_ID}?nonce=$(date +%s%N)" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/gw_publish_payload.json)
  rm -f /tmp/gw_publish_payload.json
  if [ "$CODE" != "200" ]; then
    echo "PATCH failed (HTTP $CODE)" >&2
    head -c 400 /tmp/gw_publish_resp.json >&2
    exit 1
  fi
  echo "published -> gist $GIST_ID"
fi

# --- verify（cache-buster 付きで取得して比較） ---------------------------
fail=0
for f in "${FILES[@]}"; do
  src="$DIR/$f"; [ "$f" = "README.md" ] && src="$DIR/README-gist.md"
  tmp=$(mktemp)
  curl -sSL "https://gist.githubusercontent.com/${GIST_OWNER}/${GIST_ID}/raw/${f}?cb=$(date +%s%N)" -o "$tmp"
  if cmp -s "$src" "$tmp"; then
    printf '  %-36s IDENTICAL\n' "$f"
  else
    printf '  %-36s DIFFERS  (CDNキャッシュの可能性)\n' "$f"
    fail=1
  fi
  rm -f "$tmp"
done

cat <<EOF

canonical URL (以降の publish はこのリンクへ):
  https://gist.githubusercontent.com/${GIST_OWNER}/${GIST_ID}/raw/latest.txt
EOF
[ "$fail" -eq 0 ] || { echo "WARNING: 差分あり。API 上の内容を確認してください。" >&2; exit 1; }
echo "verify: OK"
