#!/usr/bin/env bash
# =============================================================================
#  publish-repo.sh — フィルタを GitHub リポジトリへ公開（git data API）
#
#  必要スコープ:
#    classic PAT      : public_repo （または repo）
#    fine-grained PAT : Repository permissions → Contents: Read and write
#                        対象リポジトリを "Only select repositories" で選択
#
#  使い方:
#    ./publish-repo.sh                 # リポジトリ作成（無ければ）+ publish + 検証
#    ./publish-repo.sh --check         # 検証のみ
#
#  トークンの取得順:
#    1) 環境変数 GH_TOKEN
#    2) macOS キーチェーン: security find-generic-password -s gh-gist-token -w
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

TOKEN="${GH_TOKEN:-}"
if [ -z "$TOKEN" ] && command -v security >/dev/null 2>&1; then
  TOKEN="$(security find-generic-password -s "$KEYCHAIN_SVC" -w 2>/dev/null || true)"
fi
if [ -z "$TOKEN" ]; then
  cat >&2 <<'EOF'
ERROR: GitHub token が見つかりません。

  キーチェーンへ登録:
    security add-generic-password -a "$USER" -s gh-gist-token -w 'ghp_xxxxx' -U
EOF
  exit 1
fi

api() { # api <METHOD> <path> [json-body]
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS -o /tmp/gw_api_out.json -w "%{http_code}" -X "$method" "https://api.github.com${path}" \
      -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" -H "Content-Type: application/json" \
      --data-binary "$body"
  else
    curl -sS -o /tmp/gw_api_out.json -w "%{http_code}" -X "$method" "https://api.github.com${path}" \
      -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28"
  fi
}

# --- lint（publish.sh と同じ検査） ---------------------------------------
python3 - "$DIR" <<'PY'
import re, sys, os
d = sys.argv[1]; problems = []
for name in ['latest.txt','adblock-generic.txt','gamewith-adguard-filter.txt']:
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

# --- repo の存在確認 / 作成 ----------------------------------------------
CODE=$(api GET "/repos/${OWNER}/${REPO}")
if [ "$CODE" = "404" ]; then
  if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "repo ${OWNER}/${REPO} が存在しません（--check なので作成はしません）"; exit 2
  fi
  echo "repo ${OWNER}/${REPO} が存在しないため作成します…"
  CODE=$(api POST /user/repos "{\"name\":\"${REPO}\",\"description\":\"汎用 / gamewith.jp 向け アドブロックフィルタ (anti-adblock countermeasures)\",\"private\":false,\"auto_init\":true}")
  if [ "$CODE" != "201" ]; then
    echo "ERROR: リポジトリ作成に失敗 (HTTP $CODE)" >&2
    python3 - <<'PY' >&2
import json
try:
    d = json.loads(open('/tmp/gw_api_out.json', encoding='utf-8').read(), strict=False)
    print('  message:', d.get('message'))
except Exception:
    print(open('/tmp/gw_api_out.json', encoding='utf-8').read()[:300])
PY
    cat >&2 <<'EOF'

  トークンのスコープが不足しています（gist のみではリポジトリを作れません）。
  必要なもの:
    classic PAT      : public_repo スコープ
    fine-grained PAT : Repository permissions → Contents: Read and write
  新しいトークンを作り、GH_TOKEN 環境変数またはキーチェーンに設定してください。
EOF
    exit 1
  fi
  echo "created: ${OWNER}/${REPO}"
elif [ "$CODE" != "200" ]; then
  echo "ERROR: repo lookup HTTP $CODE" >&2; exit 1
fi

# --- publish（git data API） ---------------------------------------------
if [ "$CHECK_ONLY" -eq 0 ]; then
  # 1) 現在の branch head
  CODE=$(api GET "/repos/${OWNER}/${REPO}/git/ref/heads/${BRANCH}")
  BASE_SHA=""
  if [ "$CODE" = "200" ]; then
    BASE_SHA=$(python3 -c "import json;print(json.loads(open('/tmp/gw_api_out.json',encoding='utf-8').read(),strict=False)['object']['sha'])")
  else
    echo "branch ${BRANCH} が存在しないため新規作成します"
  fi

  # 2) blobs
  TREE_ENTRIES="[]"
  for f in "${FILES[@]}"; do
    src="$DIR/$f"
    BODY=$(python3 -c "
import json,sys,base64
data=open(sys.argv[1],'rb').read()
print(json.dumps({'content':base64.b64encode(data).decode(),'encoding':'base64'}))" "$src")
    CODE=$(api POST "/repos/${OWNER}/${REPO}/git/blobs" "$BODY")
    if [ "$CODE" != "201" ]; then echo "ERROR: blob $f (HTTP $CODE)" >&2; exit 1; fi
    SHA=$(python3 -c "import json;print(json.loads(open('/tmp/gw_api_out.json',encoding='utf-8').read(),strict=False)['sha'])")
    NAME="$f"
    TREE_ENTRIES=$(python3 -c "
import json,sys
t=json.loads(sys.argv[1]); t.append({'path':sys.argv[2],'mode':'100644','type':'blob','sha':sys.argv[3]})
print(json.dumps(t))" "$TREE_ENTRIES" "$NAME" "$SHA")
  done

  # 3) tree
  if [ -n "$BASE_SHA" ]; then
    BODY=$(python3 -c "import json,sys;print(json.dumps({'base_tree':sys.argv[1],'tree':json.loads(sys.argv[2])}))" "$BASE_SHA" "$TREE_ENTRIES")
  else
    BODY=$(python3 -c "import json,sys;print(json.dumps({'tree':json.loads(sys.argv[1])}))" "$TREE_ENTRIES")
  fi
  CODE=$(api POST "/repos/${OWNER}/${REPO}/git/trees" "$BODY")
  [ "$CODE" = "201" ] || { echo "ERROR: tree (HTTP $CODE)" >&2; exit 1; }
  TREE_SHA=$(python3 -c "import json;print(json.loads(open('/tmp/gw_api_out.json',encoding='utf-8').read(),strict=False)['sha'])")

  # 4) commit
  BODY=$(python3 -c "
import json,sys
print(json.dumps({'message':sys.argv[1],'tree':sys.argv[2],'parents':[sys.argv[3]]}))" \
    "chore: update filters" "$TREE_SHA" "$BASE_SHA")
  CODE=$(api POST "/repos/${OWNER}/${REPO}/git/commits" "$BODY")
  [ "$CODE" = "201" ] || { echo "ERROR: commit (HTTP $CODE)" >&2; exit 1; }
  COMMIT_SHA=$(python3 -c "import json;print(json.loads(open('/tmp/gw_api_out.json',encoding='utf-8').read(),strict=False)['sha'])")

  # 5) ref update（branch が無ければ新規作成）
  if [ -n "$BASE_SHA" ]; then
    BODY=$(python3 -c "import json,sys;print(json.dumps({'sha':sys.argv[1],'force':False}))" "$COMMIT_SHA")
    CODE=$(api PATCH "/repos/${OWNER}/${REPO}/git/refs/heads/${BRANCH}" "$BODY")
    [ "$CODE" = "200" ] || { echo "ERROR: ref update (HTTP $CODE)" >&2; exit 1; }
  else
    BODY=$(python3 -c "import json,sys;print(json.dumps({'ref':'refs/heads/'+sys.argv[2],'sha':sys.argv[1]}))" "$COMMIT_SHA" "$BRANCH")
    CODE=$(api POST "/repos/${OWNER}/${REPO}/git/refs" "$BODY")
    [ "$CODE" = "201" ] || { echo "ERROR: ref create (HTTP $CODE)" >&2; exit 1; }
  fi
  echo "published -> ${OWNER}/${REPO}@${BRANCH} (${COMMIT_SHA:0:12})"
fi

# --- verify（raw.githubusercontent から取得して比較） -----------------------
fail=0
for f in "${FILES[@]}"; do
  src="$DIR/$f"
  name="$f"
  tmp=$(mktemp)
  curl -sSL "https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}/${name}?cb=$(date +%s%N)" -o "$tmp"
  if cmp -s "$src" "$tmp"; then
    printf '  %-36s IDENTICAL\n' "$name"
  else
    printf '  %-36s DIFFERS (CDNキャッシュの可能性)\n' "$name"; fail=1
  fi
  rm -f "$tmp"
done

cat <<EOF

購読 URL（iPhone 用・常に最新を追従）:
  https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}/latest.txt
EOF
[ "$fail" -eq 0 ] || { echo "WARNING: 差分あり" >&2; exit 1; }
echo "verify: OK"
