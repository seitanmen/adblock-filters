# 汎用 / gamewith.jp 向け アドブロックフィルタ

アンチアドブロック（anti-adblock）対策を軸にした、日本語サイト向けのフィルタ群です。
調査根拠: 2026-11-06/07 に gamewith.jp を実測（Chromium + iPhone UA エミュレーション + 静的スキャン）。

## ファイル

| ファイル | 用途 |
|---|---|
| `latest.txt` | **汎用フィルタ（主）**。常に最新版に更新される固定 URL。 |
| `adblock-generic.txt` | 汎用フィルタの内容（名前付き版・`latest.txt` と同一） |
| `gamewith-adguard-filter.txt` | gamewith.jp 専用（汎用 + サイト固有の cosmetic / scriptlet / first-party 広告枠） |
| `gamewith-safari-content-blocker.json` | iOS 素の Safari Content Blocker 用（ネットワークのみ） |

## 導入（AdGuard for iOS）

1. AdGuard アプリ →「AdGuardによる保護」→「Safariでブロック」→「フィルタ」
2. 「カスタムフィルター」→「+」→「URLでフィルタを追加」
3. 下の URL を登録 → **スイッチを ON**

- 汎用: `https://gist.githubusercontent.com/seitanmen/ddee9b5f01fa9c4adaeca866ee9192c8/raw/latest.txt`
- gamewith 専用: `https://gist.githubusercontent.com/seitanmen/ddee9b5f01fa9c4adaeca866ee9192c8/raw/gamewith-adguard-filter.txt`
- 素の Safari Content Blocker 用: `https://gist.githubusercontent.com/seitanmen/ddee9b5f01fa9c4adaeca866ee9192c8/raw/gamewith-safari-content-blocker.json`

モードは **「拡張機能（ネットワーク）」** を推奨。DNS フィルタリングモードは scriptlet が実行できず、
`html-load.com` を DNS で止めると逆に偽エラー画面が出ます（Yuki2718 / AdGuard issue #213713）。

## 汎用フィルタの中身

- **[1] Ad-Shield (Raptive)**: `html-load.com` ほか recovery 関連 11 ドメインを世界中で遮断
- **[2] 改ざん検知 / recovery 抑止**: AdGuard Base（2026-11-07 時点）から抽出した既知デプロイ済み **642 ドメイン**に対し
  `trusted-replace-argument`（setAttribute フック無効化）/ `$$script[src="html-load.com/"]`（HTML フィルタ）/
  recovery 注入抑止の大型 scriptlet を適用
- **[3] Pangle / BlockThrough**: `btloader.com` / `ad-delivery.net` / `dns-finder.com` を遮断し、
  AA 検出（`localStorage.BT_AA_DETECTION` の ab/aa/nlf）が上流へ送られないようにする
- **[4] 日本の広告ネットワーク**: FLUX / Geniee / Caprofitx / Rise(Enhance) / Criteo / IntentIQ / Browsi 系 /
  Intimate Merger DMP / Twitter / Yahoo 計測 など
- **[5] 任意**: Clarity・Facebook Pixel など（コメントアウト済み）

## 注意事項

- 汎用フィルタは**ネットワーク層のみ**。広告枠の余白（空白）を消すにはサイト固有の cosmetic が必要
  （同 Gist の `gamewith-adguard-filter.txt` が例）。
- scriptlet / HTML フィルタは **AdGuard 専用**。uBlock Origin では大半が無視されます
  （uBO の upstream には Ad-Shield 専用ルールが存在しません）。
- 素の Safari Content Blocker は scriptlet 非対応。`.json` を使う場合は `.txt` と二重に有効化しないでください。
- 旧 Gist（`030e38ac…`）は legacy です。汎用ファイルは未修正（`|` 区切り）のままなので、新しい上記 URL へ付け替えてください。
