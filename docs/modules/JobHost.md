# JobHost — 実行基盤

ジョブ名から実装を引き当てて実行する基盤です。設定とジョブ定義を読み、ジョブが使うサービス（ポート）を組み立てて `Context` として渡し、結果を検証して、最後にブラウザ接続などを閉じます。公開するのは `Invoke-HostedJob` だけです。特定のジョブの名前・業務の知識は持ちません（テストで検査）。

依存: `JobKit`、`PageBridge`（Browser サービスの実装として）

## 公開関数

### `Invoke-HostedJob`

```powershell
Invoke-HostedJob -AppRoot <app> -JobName <ジョブ名> [-SettingsPath] [-CatalogPath] [-SettingsOverrides @{}] [-ServiceOverrides @{}]
```

| パラメーター | 内容 |
|---|---|
| `AppRoot` | `app` フォルダー。設定ファイルの既定の場所と、ジョブ定義の相対パスの基準。その親がプロジェクトのルート |
| `SettingsPath` / `CatalogPath` | 省略時は `app/config/settings.psd1` / `app/config/jobs.psd1` |
| `SettingsOverrides` | `Jobs.<ジョブ名>` の値をこの実行だけ上書きする（連携ジョブが成果物のパスを渡すときに使う）。パスの値は設定ファイルと同じ規則で解決する |
| `ServiceOverrides` | テスト用のサービスの差し替え（`Clock` / `ConsoleWriter` / `Transport`）。本番では指定しない。子ジョブにも引き継ぐ |

失敗はログ（`<ジョブ名> は異常終了しました: …`）に残したうえで例外として伝えます。成功・失敗にかかわらずブラウザ接続を閉じ、後始末の失敗で本来のエラーを上書きしません。

## サービス

サービスの形（メンバーとパラメーター）は [ARCHITECTURE.md](../../ARCHITECTURE.md#3-context-とサービスポート) の表を参照してください。ここでは振る舞いの約束をまとめます。

| サービス | 約束 |
|---|---|
| `Log` | `[日時] [レベル] [実行ID] メッセージ` の1行を、コンソールと（有効なら）ファイルへ書く。`Data` はオブジェクトを JSON で残す。ファイルは UTF-8（BOM 付き）で `<Directory>/<ジョブ名>_<実行ID>.log` |
| `Clock` | `Now` は現在時刻、`Sleep` は待機。テストでは手で進む時計に差し替える |
| `Files.EnsureDirectory` / `ClearDirectory` | 安全なディレクトリか確かめてから作る・空にする（下記「安全なパス」） |
| `Files.RemoveFile` | `Within` の配下にあるファイルだけを消す。消したら `$true` |
| `Files.ListFiles` | `Name` / `FullName` / `Length` / `LastWriteTime` を名前順に返す。`Filter` は名前全体へのワイルドカード一致（Windows の短い名前による誤一致を除く） |
| `Files.ReadText` / `ReadBytes` | UTF-8（BOM の有無を問わない）のテキスト / バイト列 |
| `Files.SaveCsv` | UTF-8（BOM 付き）・CRLF・全項目を引用符で囲む。0件のとき `Remove`（前回のファイルを消す）か `HeaderOnly`（見出し行だけ書く） |
| `Files.MoveToUnique` | 移動先に同名があれば `名前 (1).拡張子`… の重ならない名前にして移動し、移動先を返す |
| `Downloads.WaitForFile` | 書き込み途中のファイル（`*.crdownload` / `*.tmp` / `*.download`）が無く、候補がちょうど1つで、`StableSeconds` の間サイズが変わらず、排他で開けたら完了。候補が2つ以上なら取り違え防止のため即エラー。ダウンロード先は専用の空フォルダーを前提にする |
| `Lists.Traverse` | 表示中の行を読み、未処理の行を `Visit` し、新しい行が無ければ `ScrollNext` で進む。期待件数に達する（`expected-count`）、スクロールが `StallLimit` 回続けて動かない（`end-of-list`）、`MaxLoops` に達する（`loop-limit`）のどれかで終わり、終了理由を返す。件数が足りるかの判断は呼び出し側 |
| `Jobs.Run` | 子ジョブを `Invoke-HostedJob` で実行する。設定ファイル・ジョブ定義は親と同じものを使う（パスを受け取る口が無い） |
| `Jobs.GetSettings` | 子ジョブの設定（パス解決済みのコピー）を読む |
| `Browser` | ジョブの操作カタログに束縛された、PageBridge の窓口。`Connect` は画面識別に一致するタブを1つ選んで接続する |

### 安全なパス

中身を消すことがあるため、次の場所は作業ディレクトリとして受け付けません。

- 空のパス、ドライブ・ファイルシステムのルート
- ユーザープロファイル（ホーム）そのもの、その直下のフォルダー（Desktop、Downloads、Documents など）

ファイルの削除・CSV の出力は、許可したディレクトリの配下にあることを、パスの区切りごとに比べて確かめてから行います（`C:\work2` は `C:\work` の配下ではない）。

## 設定の読み込み

- `Common` と `Jobs` の2つの hashtable が必要です。
- キー名が `…Path` / `…Directory` の文字列はパスとして、プロジェクトのルート基準の絶対パスにします（環境変数を展開し、区切り文字を実行環境に合わせる）。
- ジョブには `Jobs.<ジョブ名>` の深いコピーを渡します。ジョブが値を書き換えても他のジョブに影響しません。
- 値の意味（必須か、整数か）は各ジョブが開始時に検証します。実行基盤が検証するのは `Common.Browser` と `Common.Logging` です。

## ファイル構成

| ファイル | 役割 |
|---|---|
| [JobHost.psm1](../../app/modules/JobHost/JobHost.psm1) | 読み込むファイルの一覧と公開関数 |
| [Public/Invoke-HostedJob.ps1](../../app/modules/JobHost/Public/Invoke-HostedJob.ps1) | ジョブの実行（読み込み → Context → 実行 → 検証 → 後始末） |
| [Private/HostPaths.ps1](../../app/modules/JobHost/Private/HostPaths.ps1) | パスの解決（環境変数・区切り文字・相対パス）と比較の規則 |
| [Private/HostSettings.ps1](../../app/modules/JobHost/Private/HostSettings.ps1) | 設定ファイルの読み込み、パスの解決、ジョブ設定のコピーと上書き |
| [Private/JobCatalog.ps1](../../app/modules/JobHost/Private/JobCatalog.ps1) | ジョブ定義（jobs.psd1）の読み込みと検証 |
| [Private/HostClock.ps1](../../app/modules/JobHost/Private/HostClock.ps1) | Clock サービス |
| [Private/HostLog.ps1](../../app/modules/JobHost/Private/HostLog.ps1) | Log サービス（レベル、書式、コンソール・ファイル） |
| [Private/SafePaths.ps1](../../app/modules/JobHost/Private/SafePaths.ps1) | 安全なディレクトリの判定と、配下にあるかの確認 |
| [Private/CsvText.ps1](../../app/modules/JobHost/Private/CsvText.ps1) | CSV の文字列化（引用符・CRLF） |
| [Private/FileService.ps1](../../app/modules/JobHost/Private/FileService.ps1) | Files サービス |
| [Private/DownloadWatcher.ps1](../../app/modules/JobHost/Private/DownloadWatcher.ps1) | Downloads サービス（ダウンロード完了の判定） |
| [Private/ListTraversal.ps1](../../app/modules/JobHost/Private/ListTraversal.ps1) | Lists サービス（スクロールする一覧のたどり方） |
| [Private/BrowserService.ps1](../../app/modules/JobHost/Private/BrowserService.ps1) | Browser サービス（`Common.Browser` の検証、PageBridge への接続） |
| [Private/ChildJobs.ps1](../../app/modules/JobHost/Private/ChildJobs.ps1) | Jobs サービス（子ジョブの実行と設定の参照） |
| [Private/RunContext.ps1](../../app/modules/JobHost/Private/RunContext.ps1) | 実行 ID、Context とサービスの組み立て、後始末 |

## テスト

| テスト | 内容 |
|---|---|
| [SettingsAndCatalog.Tests.ps1](../../tests/pester/JobHost/SettingsAndCatalog.Tests.ps1) | パスの解決、設定のコピーと上書き、ジョブ定義の検証 |
| [FilesAndSafety.Tests.ps1](../../tests/pester/JobHost/FilesAndSafety.Tests.ps1) | 安全なパス、Files サービス、CSV の書式 |
| [DownloadsAndLists.Tests.ps1](../../tests/pester/JobHost/DownloadsAndLists.Tests.ps1) | ダウンロード完了の判定、一覧のたどり方と終了理由 |
| [HostedJob.Tests.ps1](../../tests/pester/JobHost/HostedJob.Tests.ps1) | 実行の流れ、結果の検証、子ジョブへの設定・差し替えの引き継ぎ、Browser サービス |

## この文書を更新するとき

- `Invoke-HostedJob` のパラメーター、サービスの約束、設定の読み方、ファイル構成が変わったとき
