# トークンの管理と publish の使い方

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

## 4. 漏れたとき・失効する��き

- 失効: https://github.com/settings/tokens （Delete / Revoke）
- 失効後も **Gist は公開状態のまま** なので購読 URL はそのまま使えます（publish だけできなくなります）。
- 失効後は新しいトークンを B か A で登録し直してください。
- 会話ログに貼り付けたトークンは **必ず失効** してください。履歴が残ります。
