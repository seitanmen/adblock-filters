#!/usr/bin/env bash
# =============================================================================
#  publish.sh — フィルタを Gist へ公開 + 検証
#
#  使い方:
#    ./publish.sh            # 公開（git push）+ 検証
#    ./publish.sh --check    # 検証のみ
#
#  認証:
#    git push は credential helper 経由（`gh auth setup-git` 済みなら自動）。
#    検証（Gist API）は次からトークンを取得:
#      1) $GH_TOKEN  2) gh auth token  3) macOS キーチェーン
#
#  ※ 公開は git push のみを使用します。Gist の REST PATCH は
#    環境によって一部ファイルしか反映されないことがあるため。
#    https://gist.github.com/<owner>/<id>.git は普通の git remote として
#    push できるため、こちらが安定します。
# =============================================================================
set -euo pipefail

GIST_ID="${GIST_ID:-ddee9b5f01fa9c4adaeca866ee9192c8}"
GIST_OWNER="${GIST_OWNER:-seitanmen}"
KEYCHAIN_SVC="${KEYCHAIN_SVC:-gh-gist-token}"
DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

# latest.txt, adblock-generic.txt, gamewith-adguard-filter.txt,
# doublecodes-adguard-filter.txt, gamewith-safari-content-blocker.json, README.md
FILES=(latest.txt adblock-generic.txt gamewith-adguard-filter.txt doublecodes-adguard-filter.txt gamewith-safari-content-blocker.json README.md)

# --- token（検証用・任意） -------------------------------------------------
TOKEN="${GH_TOKEN:-}"
if [ -z "$TOKEN" ] && command -v gh >/dev/null 2>&1; then
  TOKEN="$(gh auth token 2>/dev/null || true)"
fi
if [ -z "$TOKEN" ] && command -v security >/dev/null 2>&1; then
  TOKEN="$(security find-generic-password -s "$KEYCHAIN_SVC" -w 2>/dev/null || true)"
fi

# --- lint（構文チェック） ---------------------------------------------------
python3 - "$DIR" <<'PY'
import re, sys, os
d = sys.argv[1]; problems = []
for name in ['latest.txt', 'adblock-generic.txt', 'gamewith-adguard-filter.txt', 'doublecodes-adguard-filter.txt']:
    p = os.path.join(d, name)
    if not os.path.exists(p): continue
    for i, line in enumerate(open(p, encoding='utf-8'), 1):
        t = line.strip()
        if not t or t.startswith('!'): continue
        if '#%#' in t:
            head = t.split('#%#')[0]
            if ',' not in head and '|' in head:
                problems.append(f'{name}:{i} scriptlet rule のドメインが | 区切り（カンマ必須）')
        elif '$$' in t:
            head = t.split('$$')[0]
            if ',' not in head and '|' in head:
                problems.append(f'{name}:{i} html-filter rule のドメインが | 区切り（カンマ必須）')
        elif '##' not in t and not re.search(r'\|\||\|http|://|\^', t):
            problems.append(f'{name}:{i} 分類できないルール: {t[:60]}')
if problems:
    print('LINT FAILED:'); [print('  -', p) for p in problems]; sys.exit(1)
print('lint: OK')
PY

# --- publish（git push） ----------------------------------------------------
if [ "$CHECK_ONLY" -eq 0 ]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  if ! git clone -q "https://gist.github.com/${GIST_OWNER}/${GIST_ID}.git" "$WORK/gist" 2>/dev/null; then
    # 初回（空の gist）の場合
    mkdir -p "$WORK/gist" && cd "$WORK/gist" && git init -q -b main
    git remote add origin "https://gist.github.com/${GIST_OWNER}/${GIST_ID}.git"
  fi
  cd "$WORK/gist"
  for f in "${FILES[@]}"; do
    src="$DIR/$f"; [ "$f" = "README.md" ] && src="$DIR/README-gist.md"
    cp "$src" "./$f"
  done
  git add -A
  if git diff --cached --quiet; then
    echo "変更なし（push はスキップ）"
  else
    git -c core.hooksPath=/dev/null commit -q -m "chore: update adblock filters"
    echo "committed: $(git rev-parse --short HEAD)"
    git push -q origin HEAD:main || { echo "ERROR: push に失敗しました" >&2; exit 1; }
    echo "published -> gist ${GIST_ID}"
  fi
fi

# --- verify（Gist API=正 / raw CDN=参考） ----------------------------------
fail=0
if [ -n "$TOKEN" ]; then
  CODE=$(curl -sS -o /tmp/gw_gist_api.json -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/gists/${GIST_ID}?cb=$(date +%s%N)")
  for f in "${FILES[@]}"; do
    src="$DIR/$f"; [ "$f" = "README.md" ] && src="$DIR/README-gist.md"
    if [ "$CODE" = "200" ]; then
      python3 - "$src" "$f" <<'PY' || fail=1
import json, sys
d = json.loads(open('/tmp/gw_gist_api.json', encoding='utf-8').read(), strict=False)
f = d['files'].get(sys.argv[2])
if not f:
    print(f'  {sys.argv[2]:36s} API: ファイルが見つかりません'); sys.exit(1)
remote = f.get('content') or ''
local = open(sys.argv[1], encoding='utf-8').read()
print(f'  {sys.argv[2]:36s} API: ' + ('IDENTICAL' if remote == local else 'DIFFERS'))
sys.exit(0 if remote == local else 1)
PY
    else
      printf '  %-36s API: HTTP %s\n' "$f" "$CODE"; fail=1
    fi
    tmp=$(mktemp)
    curl -sSL "https://gist.githubusercontent.com/${GIST_OWNER}/${GIST_ID}/raw/${f}?cb=$(date +%s%N)" -o "$tmp"
    if cmp -s "$src" "$tmp"; then
      printf '  %-36s raw: IDENTICAL\n' "$f"
    else
      printf '  %-36s raw: 古い可能性（CDNキャッシュ、数分で更新）\n' "$f"
    fi
    rm -f "$tmp"
  done
fi

cat <<EOF

canonical URL (以降の publish はこのリンクへ):
  https://gist.githubusercontent.com/${GIST_OWNER}/${GIST_ID}/raw/latest.txt
EOF
[ "$fail" -eq 0 ] || { echo "WARNING: 差分あり" >&2; exit 1; }
echo "verify: OK"
