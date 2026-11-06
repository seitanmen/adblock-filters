# gamewith.jp アンチアドブロック調査 & フィルタ

調査日: 2026-11-06 / 対象: `https://gamewith.jp`（PC・モバイル・iPhone Safari）
すべて **実測**（Chromium + Playwright、iPhone UA / 390×844 エミュレーション、curl）にもとづく結果です。

---

## 公開先（購読リンク）

| 用途 | URL |
|---|---|
| **リポジトリ（推奨・更新が早い）** | `https://raw.githubusercontent.com/seitanmen/adblock-filters/main/latest.txt` |
| Gist（ミラー） | `https://gist.githubusercontent.com/seitanmen/ddee9b5f01fa9c4adaeca866ee9192c8/raw/latest.txt` |
| gamewith 専用 | `https://raw.githubusercontent.com/seitanmen/adblock-filters/main/gamewith-adguard-filter.txt` |
| iOS 素の Content Blocker 用 | `https://raw.githubusercontent.com/seitanmen/adblock-filters/main/gamewith-safari-content-blocker.json` |

反映は `./publish-repo.sh`（lint → push → 検証つき）。手順は `TOKEN-SETUP.md` 参照。

---

## 0. 結論（TL;DR）

**gamewith.jp に「広告をブロックしたらブロックを解除しろ」と強制する仕組み（hard wall）は 2026-11-06 時点で実装されていません。**

- 広告を実際に遮断した状態（AdSense/GAM・Pangle・Flux・Geniee・Browsi を全部ブロック、cosmetic で広告枠も非表示）でも、
  トップ／記事／ゲーム別ページの **本文・レイアウトは完全に通常表示**。偽のエラーモーダルも出ない。
- 一方で **「広告ブロックを検出する」仕組みは 2 つ** あり、検出結果（adblock=true など）は広告ネットワーク側へ送信されています。
  → participation（表示回数）に影響し、延命広告やRetry が起きうる、というのが実害。
- 実装されているのは **Ad-Shield（= Raptive AdShield, `html-load.com`）**。
  **Chromium 実測では「偽エラー画面」の発火を再現できませんでした**
  （`html-load.com` をネットワーク遮断しても DOM・CSS とも無傷。静的スキャンでも
  first-party 側に gate / modal / メッセージは一切なし）。
  ただし `core.js` には **iOS 固有の短絡分岐**があり（後述）、Chromium エミュレーションの結果は
  **実機 iOS Safari の挙動を証明しません**。実機・アプリ内での発生は複数のユーザー報告と
  App Store レビューで報告されています。

---

## 1. 実測した仕組み（4 層）

### ① Ad-Shield（`html-load.com`）— サーバー側注入
ゲーム別ページ（`/pokemon-tcg-pocket/` `/shironeko/` `/fgo/` `/xenoblade/article/show/207982` など）の **サーバー HTML** に:

```html
<script async id="OtXIYzvBmteMxc" data-sdk="l/1.2.3" data-cfasync="false" nowprocket
        src="https://html-load.com/core.js" onload="(()=>{...難読化...})()">
<script data-cfasync="false" nowprocket>(()=>{...難読化デコーダ...})();</script>
```

- `data-sdk="l/1.2.3"` / `nowprocket`（Cloudflare Rocket Loader を意図的に回避）は Ad-Shield 固有の指紋。
- **PC / モバイル（iPhone UA）で同一**。トップ（`/`）と汎用 PC 記事（`/pc/article/show/*`）には入っていない。
- 関連ドメイン: `html-load.com` / `fb.html-load.com`（フォールバック）/ `v.html-load.com` + `video-loads.com`（動画用）/ `error-report.com`（偽エラー表示）。
- ローダーは **実行後自身を DOM から削除**する（`window.adshield = {loaded:true, cmd:{}}`）。
- `core.js` 内の実測文字列:
  - `"[AdBlockDetector] Cosmetic adblock detected"` / `"[AdBlockDetector] Snippet adblock detected"` /
    `"[AdBlockDetector] Request adblock detected. "` → cosmetic / snippet / request の 3 経路で検出
  - baits: `pub_300x250`, `pub_300x250m`, `pub_728x90`, `text-ad-links`, `adsbygoogle`, `ad-unit`, `banner-ad`, `div#contents > span#ads`
  - `is_admiral_adwall_rendered` / `raptive_is_blocking_ads` / `hostage` / `cache_is_blocking_ads`
  - 環境改変フック: `XMLHttpRequest_open/send/response`, `Window_fetch`, `Element_innerHTML`,
    `Element_insertAdjacentHTML`, `HTMLScriptElement_src`, `Document_write`, `Function_toString` …
    （検出回避と `[native code]` 偽装）
  - `https://report.error-report.com/modal?...&error=Vml0YWwgQVBJIGJsb2NrZWQ%3D&domain=`
    → `error=` の base64 = **"Vital API blocked"**
  - `document.querySelectorAll('link,style')` による **CSS 破壊**
  - base64 `UGxlYXNlIGFsbG93IGFkcyBvbiB0aGlzIHNpdGUuIENsaWNrIE9LIHRoZW4gbGVhcm4gbW9yZS4`
    → **"Please allow ads on this site. Click OK to learn more."**（英語のみ）
  - iOS 固有の短絡: `[AdBlockDetector] request filter check abandoned due to visibility change (iOS process suspend)` /
    `... page hidden (iOS)`、`/iPhone|iPad|iPod/` UA 分岐で request-filter チェックを **スキップ**
- ローダーが入るのは **GPT 広告枠を持つページと完全に一致**（トップ・`/appli/`・一部 DB テンプレートには無い）。
- **AdGuard の Base フィルタには既に入っています**（`BaseFilter/sections/specific.txt` の
  `||html-load.com^$script,important,domain=...gamewith.jp...`、`trusted-replace-argument` による setAttribute 改ざん検知の無効化、
  `$$script[src="html-load.com/"]`、`$$script:contains(...)`、recovery 注入抑止の大型 scriptlet）。

### ② Pangle / ByteDance（`btloader.com`）— AA 検出
実測ロードチェーン:

```
gamewith.jp
 └─ flux-cdn.com/client/gamewith/gamewith-jp2.min.js
     └─ pbFlux.importTag("https://btloader.com/tag?o=5727730570625024&upapi=true")   ← 実測コード
         └─ Pangle タグが AA 検出を実行
             └─ localStorage["BT_AA_DETECTION"] = {"ab":..,"aa":..,"nlf":..}
```

検出の実装（`btloader.com/tag` のコードから確認）:

| 種別 | bait | 用途 |
|---|---|---|
| `ab` | `https://ad-delivery.net/px.gif?ch=2&e=…` | 広告ブロック遮断検知 |
| `ab` | `https://ad.doubleclick.net/favicon.ico?ad=300x250&…` | 同上 |
| `ab` | 隠し要素 `class="ad_row adbannertop ad-mobile ad_sidebar adpopup boxad contentAd"` | cosmetic 検知 |
| `aa` | `https://ad-delivery.net/px.gif?ch=1&e=…` | 「許容広告」と「ブロック」の区別 |
| `nlf` | `https://ab.dns-finder.com/meta/dns`, `https://wb.dns-finder.com/meta/dns` | **DNS レベル遮断（uBO の DNS フィルタ等）の検知** |

- baits の **60% 以上が失敗すると `ab=true`**。実測: 広告を遮断した環境では `{"ab":true,"aa":false,"nlf":false}` になりました。
- 結果キャッシュは `localStorage.BT_AA_DETECTION`、さらに `BT_device`（51Degrees によるデバイス識別）、`BT_tpc`（Third-Party Cookie 可否）、
  `btUserCountry` / `btUserIsFromRestrictedCountry`（地域制限）も同時に書き込まれます。
- **重要**: `btloader.com/websiteconfig?o=5727730570625024&w=gamewith.jp` を取得すると
  `messageWall.enabled = false`, `wall_mode = 0`, `page_views_to_render = 0`。
  → **このアカウントでは wall（強制広告表示）が無効**。コードには recovery/wall の仕組み（`wall_mode: hard/soft`、
  `allow_render_to_aa_users`）が含まれるが、gamewith 用に有効化されていない。
- なお Pangle タグは **トップで起動**（ゲーム別ページでは `BT_AA_DETECTION` は未生成）。

### ③ ゲームウィズ独自（first-party）の広告管理
`assets.gamewith.jp/js/dist/jp/gamewith/ad/index.js`（実読）:

- Google Ad Manager **network 26172165** + `googletag.defineSlot` による dozens のスロット。
- Prebid ヘッダービディング: **PubMatic / Rubicon / YIELDONE / AppNexus**、bidder に `pbFlux`（FLUX）。
- インタースティシャル: `/26172165/gw_interstitial`（OutOfPageFormat.INTERSTITIAL）— ただし各ページの
  `js-gwad` パラメータでは `displayGoogleInterstitialAd: false`（実測）。
- オーバーレイ広告: `pc_overlay` / `sp_overlay`（別アカウント `1602044336105` = Pangle 側の GAM アカウント）。
- 広告枠 ID は `div-gpt-ad-<id>-<n>` 形式。**遮断すると枠だけ残り 250px などの空白が残る**ので cosmetic で消すべき。
- 另有「jack」系オーバーレイ（`/26172165/pc_overlay`、`*_jack_ad/images/`、`walkthrough/adjack.js`）。

### ④ モバイル / iPhone 固有（実測: iPhone UA, 390×844）

**サーバー側は UA で分岐**（`Vary: User-Agent` は無く、挙動ベース分流）:
`isMobile=true` / `DFPTargetOS="iOS"` / `isWalkthroughStickyAd=true`（PC は false）。

| 実測要素 | 内容 |
|---|---|
| `.to-btn-area` | `position:fixed; bottom:0; z-index:50` / 高さ **138px**。内側に `.to-btn-area__actions`（アプリ導線）と **`.c-sp-leaderboard-ad-overlay`**（広告 h=100 → `div-gpt-ad-1513304862927-0` = `/26172165/sp_bottom_native`）。**閉じるボタンが無い**（PC 側は `#gStickyAd` + `#gCloseButton` あり） |
| `.gdb-cta-banner` | 検索CTAインタースティシャル。`z-index:2147483647` + `.overlay-layer` `z-index:2147483646`、`data-device="sp"`、**48px の閉じるボタンあり**、`discarded-search-interstitial-cta-banner` cookie で制御 |
| `.c-sp-leaderboard-ad.ad-sp-header` | モバイルヘッダー広告（h=122 / 16:9）。`isHeaderCreativeAdEnabled:false` で現在は無効 |
| `sp_*` 枠 | `sp_header` / `sp_bottom_native` / `sp_menu_top` / `sp_inarticle_top_native` / `sp_inarticle_4..20` / `sp_under_article_native` / `sp_gamedb_*` / `sp_native_ranking_*` / `sp_QA_gw` 等 20 種以上（PC は `pc_side_left` / `pc_side_right` / `pc_footer` / `pc_overlay`） |
| Browsi / safeframe | モバイルでは Browsi ネイティブ広告が自動挿入され、クリエイティブは `*.safeframe.googlesyndication.com` の入れ子 iframe で配信 |

**iOS 固有の差分（実測 / コード）**:
- `ad/index.js` の広告リフレッシュループは `if (isIOS()) return;` → **スクロール連動の再リクエストは iOS で無効**（枠数ではなく回数だけの差）。
- アプリ内 WebView（`jp.gamewith/2.16.0` UA）は `DFPTargetOS="iOS_App"` / `DFPTargetInApp="molded"` /
  `isHideOverlay:true` → 下部固定バナーは出ないが、**Ad-Shield ローダーは依然ロードされる**。
- `displayGoogleInterstitialAd` / `isHeaderCreativeAdEnabled` は **全テストページで false**。
- Turnstile / reCAPTCHA はモバイル HTML に含まれない（PC のみ）。
- App Store レビュー（v2.12.0, 2026-04-20）: アプリ版で「広告を表示できるようにしてくれ」の画面が出て
  **記事を読めなくなる**。広告ブロックを解除しても同じ画面 ⇒ **アプリ内 WebView でも Ad-Shield のゲートが効く**。
- 唯一公に認められた「閉じられない全画面広告」事例（告知 `gamewith.jp/article/show/562534`, 2026-06-01）は **PC 版のみ**と明記。

---

## 1.5 最終検証（成果物ファイルをそのまま適用、2026-11-06）

`gamewith-adguard-filter.txt` を実ファイルからパースし、ネットワークルール 50 本・cosmetic 39 本を
そのまま適用（scriptlet / HTML フィルタはエンジン依存のため本テスト対象外）。

| 端末 | ページ | GAM枠(可視/総数) | モバイル下部広告 | 本文文字数 | オーバーレイ | 壁表示 |
|---|---|---|---|---|---|---|
| Desktop | /pokemon-tcg-pocket/ | 4/4 → **0/4** | — | 11150 → 10590 | 0 | なし |
| Desktop | /shironeko/ | 4/4 → **0/4** | — | 7427 → 6981 | 0 | なし |
| Desktop | /fgo/ | 4/4 → **0/4** | — | 9040 → 8468 | 0 | なし |
| Desktop | / (トップ) | 0/0 → 0/0 | — | 24339 → 24004 | 0 | なし |
| iPhone | /pokemon-tcg-pocket/ | 2/2 → **0/2** | 100px → **0px** | 10548 → 10089 | 2※ | なし |
| iPhone | /shironeko/ | 2/2 → **0/2** | 100px → **0px** | 6887 → 6428 | 2※ | なし |
| iPhone | /fgo/ | 2/2 → **0/2** | 100px → **0px** | 8391 → 7932 | 2※ | なし |
| iPhone | / (トップ) | 0/0 → 0/0 | 61px → **0px** | 24083 → 23748 | 0 | なし |

- 文字数の減少（400〜570 文字）は **広告・benius.persistence 近い広告コピーそのものの消失**であり、本文は保持されている。
- ※ iPhone の "オーバーレイ 2" はサイト_rwownのナビゲーション/ハンバーガーメニューで、広告ではない。
- どの条件でも「allow ads」「first party video」「tainted」「error-report」の文字列は出現せず、
  偽エラー画面・403・チャレンジページも発生しなかった。
- Ad-Shield リクエスト（`html-load.com/core.js`、`fb.html-load.com/core.js`）は全ページで遮断された。

---

## 2. 生成物

| ファイル | 用途 |
|---|---|
| `gamewith-adguard-filter.txt` | **AdGuard / uBlock Origin 用フィルタ**（184 行・コメント付き）。AdGuard for Windows/Mac/iOS/Android + uBO で使える。 |
| `gamewith-safari-content-blocker.json` | **iOS Safari ネイティブ Content Blocker 用 JSON**（ネットワーク遮断のみ = 1Blocker / Hush 等用）。 |
| `README.md` | 本ファイル（調査結果 + 導入手順）。 |

フィルタの中身:

- **[1] Ad-Shield**: `html-load.com` 系を遮断 + 改ざん検知の無効化 + recovery 注入抑止（upstream AdGuard Base から
  `domain=gamewith.jp` のみに絞って引用。**書き換えではなく逐語引用**）。
- **[2] Pangle 検出**: `btloader.com` / `ad-delivery.net` / `dns-finder.com` を遮断 → 検出自体を無効化。
- **[3] first-party 広告リソース**: `*/gamewith/ad/index.js`（GAM + Prebid まとめて停止）、`walkthrough/adjack.js`、`*_jack_ad/`、`/ad/gamedboverlay/`。
- **[4] cosmetic**: 実測した DOM セレクタのみ（`div[id^="div-gpt-ad-"]`, `.js-ad-jack`, `.gdb-cta-banner-outer`, `.browsi-atf` 等）。
- **[5] サードパーティ**（任意）: doubleclick / googlesyndication / flux-cdn / geniee / intentiq / pbxai / twitter / yahoo。
- **[6] モバイル**: 下部固定バナー、`.to-btn-area`（アプリ導線・任意）。
- **[7] やってはいけないこと**: `$generichide`、CSS 資産の遮断、`body` 级的 cosmetic、Ad-Shield 対策の無効化。

---

## 3. 導入方法

### iPhone（推奨: AdGuard for iOS / AdGuard for Safari 拡張）
1. App Store から **AdGuard for iOS** を入れる（または App Store 版 Safari 拡張）。
2. 設定 → フィルタ → カスタム フィルタ リスト → 追加 → `gamewith-adguard-filter.txt` の内容を貼り付け／URL 登録。
3. AdGuard for iOS は自前エンジンなので **cosmetic と scriptlet が動きます**。
   → iPhone では cosmetic が使えない素の Safari Content Blocker よりこちらを推奨します（広告枠の空白が残るため）。

### iPhone（素の Safari Content Blocker を使う場合）
`gamewith-safari-content-blocker.json` を 1Blocker / Hush / Blocker などのアプリに読み込ませます。

- **ネットワーク遮断のみ**です（WebKit の Content Blocker は cosmetic・scriptlet 非対応）。
- ⚠️ **DNS フィルタだけでは Ad-Shield を倒せません。** `html-load.com` は first-party 扱いなので、
  DNS ブロックは「広告を消して壁を出す」反而になります（Yuki2718 / AdGuard issue #213713）。
  → iPhone では **コンテンツブロッカー（AdGuard for iOS の Safari 拡張）と併用**してください。
- アプリ内 WebView（GameWith アプリ）には Safari の Content Blocker が適用されないため、
  アプリ内の「広告を表示できるようにしてくれ」ゲートはブラウザ側の対策では消せません。
  - 結果: 広告リクエストは止まりますが、**空の広告枠（白い空白）が残ります**。
  - Ad-Shield の偽エラーを確実に無効化したい場合は、素の Content Blocker ではなく AdGuard for iOS を使ってください。
- `if-domain` は WebKit 実装により **トップ_LEVEL ドメイン**に対して評価されます。動作しない場合は `if-domain` を削除して
  全体ブロックにしてください（`gamewith-safari-content-blocker.json` を編集）。

### PC（AdGuard for Windows / macOS、Chrome 拡張など）
同じ `gamewith-adguard-filter.txt` をそのまま追加できます。AdGuard Base フィルタとの併用を推奨
（Ad-Shield 対応の二重化、uBO は `$$`（HTML フィルタ）と `#%#//scriptlet(...)` を一部無視します）。

---

## 4. 検証方法（再現手順）

```bash
# 1) Ad-Shield ローダーが 서버 HTML に含まれるか（ゲーム別ページだけ yes）
curl -sS -A "<iPhone UA>" https://gamewith.jp/pokemon-tcg-pocket/ | grep -o 'html-load.com' | head

# 2) Pangle タグのロード元
curl -sS https://flux-cdn.com/client/gamewith/gamewith-jp2.min.js | grep -o 'btloader.com/tag[^"]*'

# 3) wall が有効か（gamewith は enabled=false）
curl -sS "https://btloader.com/websiteconfig?bt_env=prod&o=5727730570625024&w=gamewith.jp" | jq .messageWall

# 4) 検出結果の実測値（ブラウザコンソール）
#    localStorage.getItem('BT_AA_DETECTION')  → {"ab":true,"aa":false,"nlf":false}
```

ブラウザ実測（Playwright）で「全広告ネットワーク遮断 + cosmetic 適用」しても、
本文テキスト長・CSSリンク数・オーバーレイの有無を計測し、遮断前後で差分がないことを確認済み
（対象: `/`, `/pokemon-tcg-pocket/`, `/shironeko/`, `/fgo/`、Desktop + iPhone エミュレーション）。

---

## 4.5 広告ネットワークの実態（実リクエストから）

記事ページ 174 リクエスト / 43 ホスト、**攻略（walkthrough）ページは 979 リクエスト / 219 ホスト**。

主要ネットワーク: Google Ad Manager (26172165) / Google Funding Choices /
FLUX + Prebid (PubMatic・Rubicon・YIELDONE・AppNexus) / Pangle (btloader) /
**Caprofitx**（`ins.adsbygoogle` を注入） / **Rise (Enhance)**（`#ads-ADU-09YVH64Z`） /
**Criteo** / **Aladdin Geniee** / Geniee Prebid / Browsi / IntentIQ / Bidswitch / 3lift /
creativecdn / Opera AdX / Yahoo / X(Twitter) / Cloudflare Turnstile（BBS 報告フォームのみ）。

その他判明した点:
- `span.js-ad-disabled[data-is-ad-disabled]` が `"1"` の場合、**サイト側が自ら広告枠を落とす**（検出ではなく実装上の抑制）。
- `navigator.webdriver` は **Turnstile の計測のみ**（2% サンプリング → Sentry）。ページ判定には使っていない。
- **Flux バンドル内に FingerprintJS v3 の `domBlockers`** があり、uBO/AdGuard/ABP 等の存在を
  デバイス指紋 `__flux_u` に折りたたんでいる（UI 表示・ゲートはなし）。
- bot UA（Googlebot / Bingbot / Applebot）でもコンテンツ配信に差分なし。adblock クライアント向けの
  403/503/challenge ページも **一切なし**。

## 5. 出典

- AdGuard 本家フィルタ（gamewith.jp 登録済みの upstream ルール／本ファイルはこの一部を逐語引用）
  - `AdguardTeam/AdguardFilters` → `BaseFilter/sections/specific.txt`（`html-load.com` 行、`trusted-replace-argument` 行、`$$script[src="html-load.com/"]` 行、recovery 抑止 scriptlet 行）
  - `AdguardTeam/AdguardFilters` → `JapaneseFilter/sections/specific.txt`（gamewith.jp の cosmetic ルール群）
- コミュニティ報告（実測では再現しなかったもの Blocking を含む／参考）:
  - AdGuard issue #214122 / #222065 / #224829 / #210688 / #213713（`A: Ad-Shield` ラベル付き）
  - HaGeZi dns-blocklists issue #10512（iOS + `gamewith.jp/pokemon-tcg-pocket/` で "Please allow ads" / "First party video error"）
  - なんJ AdGuard 部 Wiki「不具合・広告相談所」（PC で表示が崩れるという報告）
- **モバイル/iOS 固有の一次情報**
  - AdGuard issue **#213713**（`A: Ad-Shield`, P1）— iOS 26.3.1 / AdGuard for iOS 4.5.x で gamewith が閲覧不能。Yuki2718「Ad-Shield は DNS ブロックではブロックできません」
  - AdGuard issue **#214122** — iOS / Android 共通でレイアウト破壊
  - なんJ AdGuard 部 Wiki: 「iOSでad shieldでサイトが見れなくなる」(2025-08-17, iPhone 14 Plus / iOS 18.6)、「GameWithのサイトの広告ブロックができない」(2025-09-19)
  - App Store JP レビュー: 「html-loadによる強制広告に反対します」(2025-10-30)、「全画面に表示される広告になり…とじるボタンも別の広告で隠して」(2025-06-24)
  - GameWith 公式告知 `https://gamewith.jp/article/show/562534`（2026-06-01、全画面広告の閉じるボタン無効 → **PC 版のみ**と明記）
- 補足: uBlock Origin の uAssets / Yuki2718 adblock2 japanese には gamewith 固有ルールが **無い**（uBO 単体では対策にならない）

## 6. 未確認・注意

- **偽エラーモーダル（"Please allow ads"）の発火条件は Chromium では再現できませんでした。**
  Chromium で `html-load.com` を遮断してもページは無傷でした。静的スキャンでも first-party 側の
  gate / modal / メッセージはゼロでした。ただし `core.js` には
  **iPhone/iPad/iPod UA で request-filter チェックをスキップする分岐**があり、
  `document.querySelectorAll('link,style')` による CSS 破壊は **iOS で特に問題化**すると報告されています
  （AdGuard ブログも iOS を名指し）。
  → **実機 iOS Safari / アプリ内 WebView では wall が発火する可能性が高く**、
  本フィルタでは Ad-Shield 対策（[1] の scriptlet 群 + HTML フィルタ）を**必須**として扱っています。
  実機 WebKit での再現は本調査の範囲外（WebKit 実機環境なし）である点を明記します。
- `btloader.com` の `wall_mode` / `allow_render_to_aa_users` は **アカウント設定で変えられます**。
  将来「強制 wall」が有効化された場合は、検出結果の caching（`BT_AA_DETECTION`）を消すと即座に再判定されます。
- 本フィルタは 2026-11-06 時点の DOM・実装に基づくため、站点側の改修でselector が変わる可能性があります。
