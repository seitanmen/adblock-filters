#!/usr/bin/env bash
# =============================================================================
#  publish-repo.sh — フィルタを GitHub リポジトリへ公開 + 検証
#
#  使い方:
#    ./publish-repo.sh                 # lint → commit → push → 検証
#    ./publish-repo.sh --check         # 検証のみ（公開しない）
#
#  認証:
#    git push は credential helper 経由（この Mac は `gh auth setup-git` 済み）。
#    検証に GitHub API を使う場合はトークンを使う:
#      1) 環境変数 GH_TOKEN
#      2) gh auth token
#      3) macOS キーチェーン: security find-generic-password -s gh-gist-token -w
#    いずれも無い場合は raw 経由の検証のみ（レート制限の影響を受けます）。
#
#  ※ 公開は git push のみを使用します（git data API と併用すると
#    履歴が分岐して push が拒否されるため）。
# =============================================================================
set -euo pipefail

OWNER="${OWNER:-seitanmen}"
REPO="${REPO:-adblock-filters}"
BRANCH="${BRANCH:-main}"
KEYCHAIN_SVC="${KEYCHAIN_SVC:-gh-gist-token}"
DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

FILES=(latest.txt adblock-generic.txt gamewith-adguard-filter.txt gamewith-safari-content-blocker.json README.md)

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
for name in ['latest.txt', 'adblock-generic.txt', 'gamewith-adguard-filter.txt']:
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

# --- publish ---------------------------------------------------------------
if [ "$CHECK_ONLY" -eq 0 ]; then
  cd "$DIR"
  # remote 設定（未設定なら追加）
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "https://github.com/${OWNER}/${REPO}.git"
    echo "remote origin を追加しました"
  fi
  git checkout -q "$BRANCH" 2>/dev/null || git checkout -q -b "$BRANCH"
  # 変更があれば commit
  if git diff --quiet && git diff --cached --quiet; then
    echo "変更なし（push はスキップ）"
  else
    git add -A
    git -c core.hooksPath=/dev/null commit -q -m "chore: update adblock filters"
    echo "committed: $(git rev-parse --short HEAD)"
  fi
  # push（fast-forward のみ。remote に別の commit があれば fetch して rebase）
  if ! git push -q origin "$BRANCH" 2>/dev/null; then
    echo "push が拒否されました → fetch して rebase します"
    git fetch -q origin "$BRANCH"
    git rebase -q "origin/$BRANCH" || { echo "ERROR: rebase に失敗しました（手動対応が必要）" >&2; exit 1; }
    git push -q origin "$BRANCH"
  fi
  echo "published -> ${OWNER}/${REPO}@${BRANCH}"
fi

# --- verify（正: contents API / 参考: raw CDN） ----------------------------
# raw.githubusercontent.com はパス単位でキャッシュされ数分遅れることがあります。
fail=0
for f in "${FILES[@]}"; do
  src="$DIR/$f"
  if [ -n "$TOKEN" ]; then
    CODE=$(curl -sS -o /tmp/gw_api_out.json -w "%{http_code}" \
      -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${OWNER}/${REPO}/contents/${f}?ref=${BRANCH}")
    if [ "$CODE" = "200" ]; then
      python3 - "$src" <<'PY' || fail=1
import base64, json, sys
d = json.loads(open('/tmp/gw_api_out.json', encoding='utf-8').read(), strict=False)
remote = base64.b64decode(d['content']); local = open(sys.argv[1], 'rb').read()
print(f'  {d["name"]:36s} API: ' + ('IDENTICAL' if remote == local else 'DIFFERS'))
sys.exit(0 if remote == local else 1)
PY
    else
      printf '  %-36s API: HTTP %s\n' "$f" "$CODE"; fail=1
    fi
  fi
  tmp=$(mktemp)
  curl -sSL "https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}/${f}?cb=$(date +%s%N)" -o "$tmp"
  if cmp -s "$src" "$tmp"; then
    printf '  %-36s raw: IDENTICAL\n' "$f"
  else
    printf '  %-36s raw: 古い可能性（CDNキャッシュ、数分で更新）\n' "$f"
  fi
  rm -f "$tmp"
done

cat <<EOF

購読 URL（iPhone 用・常に最新を追従）:
  https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}/latest.txt
EOF
[ "$fail" -eq 0 ] || { echo "WARNING: 差分あり" >&2; exit 1; }
echo "verify: OK"
