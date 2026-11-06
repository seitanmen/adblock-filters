# トークンの管理と publish の使い方

## 0. 最短手順（この Mac で完結・トークン手渡し不要）

この Mac は `gh` CLI が `seitanmen` として `repo` スコープでログイン済み（キーリング保管）です。
したがって **新しいトークンを作る必要はありません**。

```bash
cd /Users/seitan/Desktop/work/adblock

# 方法 A: スクリプトで publish（lint + push + 検証つき）
GH_TOKEN="$(gh auth token)" ./publish-repo.sh

# 方法 B: 通常の git _push（credential helper は設定済み）
git add -A && git commit -m "..." && git push
```

上の repo 作成・commit 取得・検証はすべてスクリプト内で行われます。
`publish-repo.sh` は **branch が無い場合（空 repo）も新規作成**できるようにしてあります。

## 1. トークンを置く場所（推奨順）

### A. macOS キーチェーン（推奨・平文がディスクに残りません）

```bash
security add-generic-password -a "$USER" -s gh-gist-token -w 'ghp_xxxxxxxxxxxx' -U
```

- 確認: `security find-generic-password -s gh-gist-token -w`
- 削除: `security delete-generic-password -s gh-gist-token`
- `publish.sh` は **自動で** ここから読みます（`GH_TOKEN` が無い場合）。
- 注意: キーチェーンがロック 걸려いれば macOS が一度アクセス許可を聞きます。

### B. `~/.zshenv`（簡易・平文）

```bash
printf "export GH_TOKEN='ghp_xxxxxxxxxxxx'\n" >> ~/.zshenv
chmod 600 ~/.zshenv
```

- `~/.zshenv` は **対話・非対話を問わずすべての zsh** で読まれるため、opencode 等のツールからも参照できます。
  （`~/.zshrc` は非対話シェルでは読まれないため **不可**）
- 平文で残ります。社内ルールで禁止されている場合は A を使うか、1Password / Bitwarden CLI などに差し替えてください。

### C. 一時的に使うだけ

```bash
GH_TOKEN='ghp_xxxxxxxxxxxx' ./publish.sh
```

## 2. トークンに必要な権限

- **classic PAT** … 必要なのは `gist` スコープのみ（それだけでublish 可能。repo 権限は不要）。
- **fine-grained PAT**（推奨）: https://github.com/settings/personal-access-tokens/new
  - Permissions → **Gists: Read and write**
  - Repository access は 「Only select repositories」 で対象を指定
  - **Expiration** を設定（30/90 日）
  - 自分のアカウントの Gist にしか書き込めないため、被害が局限されます。

## 3. publish の使い方

```bash
cd /Users/seitan/Desktop/work/adblock
./publish.sh            # lint → Gist へ反映 → 取得して byte 一致検証
./publish.sh --check    # 検証のみ（公開しない）
```

`publish.sh` が行うこと:

1. **lint** — scriptlet / HTML フィルタのドメイン区切り（カンマ必須）、未分類ルールの検出
2. **PATCH** — `Gist` のファイル群を更新（`latest.txt` / `adblock-generic.txt` / `gamewith-adguard-filter.txt` /
   `gamewith-safari-content-blocker.json` / `README.md`）
3. **verify** — 認証なしで stable URL から取得し、ローカルと byte 比較
   （cache-buster 付きで取得するため、CDN キャッシュの stale contents に引っかからない）

対象 Gist（固定・今後ここだけ更新します）:

```
https://gist.github.com/seitanmen/ddee9b5f01fa9c4adaeca866ee9192c8
```

購読 URL（iPhone 用・常に最新を追従）:

```
https://gist.githubusercontent.com/seitanmen/ddee9b5f01fa9c4adaeca866ee9192c8/raw/latest.txt
```

## 4. リポジトリへ公開する場合（Gist ではなく repo を使う）

ローカル側はこのディレクトリを git リポジトリとして初期化済み（`.gitignore` 付き、`publish-repo.sh` 同梱）。

```bash
cd /Users/seitan/Desktop/work/adblock
./publish-repo.sh          # repo 作成（無ければ）+ publish + 検証
./publish-repo.sh --check  # 検証のみ
```

`publish-repo.sh` は **git data API**（blob → tree → commit → ref update）で push するため、git CLI を使わなくてよいです。

### 必要なスコープ

| トークン種 | 必要な権限 | リポジトリ作成 |
|---|---|---|
| classic PAT | `public_repo` | スクリプトが自動作成 |
| fine-grained PAT | Repository permissions → **Contents: Read and write** | **作成は不可**（Web UI で先に作成が必要） |

> fine-grained PAT ではリポジトリそのものを作れません。下の「A」を推奨します。

### A. 推奨（Web UI で repo を作ってから）

1. https://github.com/new → リポジトリ名 `adblock-filters`、**Public**、README は作らない
2. https://github.com/settings/personal-access-tokens/new → Fine-grained token
   - **Repository access**: Only select repositories → `adblock-filters` を選ぶ
   - **Permissions → Repository permissions → Contents**: Read and write
   - **Expiration**: 30 / 90 日
3. トークンを保存:
   ```bash
   security add-generic-password -a "$USER" -s gh-gist-token -w 'github_pat_xxxxx' -U
   ```
4. `./publish-repo.sh` を実行

### B. classic PAT で全部やる

1. https://github.com/settings/tokens/new → **`public_repo`** にチェック（他は不要）
2. `security add-generic-password -a "$USER" -s gh-gist-token -w 'ghp_xxxxx' -U`
3. `./publish-repo.sh`（リポジトリが無ければ自動作成）

### publish 後の購読 URL

```
https://raw.githubusercontent.com/seitanmen/adblock-filters/main/latest.txt
```

`raw.githubusercontent.com` は CDN キャッシュが短いため、更新は数分以内に反映されます
（Gist の `/raw/<file>` より反映が早い）。

## 5. 漏れたとき・失効するとき

- 失効: https://github.com/settings/tokens （Delete / Revoke）
- 失効後も **Gist は公開状態のまま** なので購読 URL はそのまま使えます（publish だけできなくなります）。
- 失効後は新しいトークンを B か A で登録し直してください。
- 会話ログに貼り付けたトークンは **必ず失効** してください。履歴が残ります。
