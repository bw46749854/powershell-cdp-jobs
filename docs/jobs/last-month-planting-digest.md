# LastMonthPlantingDigest — 先月の定植の集約

区画ごとの作付け記録 CSV（[PlantingRecordExport](planting-record-export.md) の出力）をすべて読み、**先月に定植した**作付けだけを1つの CSV に集めます。ブラウザは使いません。月次の連携ジョブ [MonthlyPlantingReport](monthly-planting-report.md) の後段です。

| 項目 | 内容 |
|---|---|
| 入力 | `TargetDirectory` の `*.csv`（自分の出力ファイル2つを除く。名前順に読む） |
| 出力 | `TargetDirectory` に `OutputCsvFileName`（必ず作る）と `FailureCsvFileName`（1件以上あるときだけ） |
| 設定 | [Jobs.LastMonthPlantingDigest](../guides/configuration.md#jobslastmonthplantingdigest) |

ファイルや行に問題があっても、それを失敗一覧に残して処理を続け、**ジョブ自体は正常終了**します。集計結果と失敗一覧を担当者が確かめる運用です。

## 規則

| 項目 | 規則 |
|---|---|
| 対象期間 | 実行日の前月1日 **以上**、当月1日 **未満**（例: 4月15日の実行なら 3月1日〜3月31日。1月の実行なら前年12月） |
| 区画コード | ファイル名から `FileNamePattern` のグループ1で取り出す。大文字・小文字を区別する |
| 文字コード | BOM 付きの UTF-8 / UTF-16 LE・BE / UTF-32 LE・BE、BOM なしの UTF-8。それ以外（Shift_JIS など）は推測で変換せず、推定した文字コードを添えて失敗にする |
| 区切り文字 | 1行目にタブがあればタブ区切り、無ければカンマ区切り |
| 引用符 | 項目内の区切り文字・改行・`""`（二重引用符）を扱う。引用符が閉じていなければ、その開始行を添えて失敗にする |
| 見出し | `RequiredHeaders` と**名前・順序・過不足・重複のすべて**が一致すること（`作物名`・`品種`・`定植日` は必須） |
| 定植日 | `yyyy-MM-dd`、`yyyy/M/d`、時刻付き、`yyyy年M月d日` など（[Policy.ps1](../../app/modules/LastMonthPlantingDigest/Private/Policy.ps1)）。読めない行は失敗にしてその行だけ飛ばす |
| 空行 | 読み飛ばす（行番号は数え続ける） |

### 失敗の扱い

| 問題 | 単位 | 失敗一覧の理由（抜粋） |
|---|---|---|
| ファイル名が `FileNamePattern` に合わない | ファイルを飛ばす | `…形式に合いません: <ファイル名>` |
| 文字コードを読めない（空のファイルを含む） | ファイルを飛ばす | `文字コードを読めないためファイルを飛ばしました: …（推定: Shift_JIS）` |
| CSV として解析できない | ファイルを飛ばす | `CSV として解析できないため…: 引用符が閉じていません（N 行目から）` |
| 見出しが一致しない | ファイルを飛ばす | `見出しが一致しません… 不足=… 余分=… 順序一致=False …ファイルを飛ばしました` |
| 列の数が見出しと違う・見出しの重複 | 行を飛ばす | `行の形が崩れているため飛ばしました: 見出しの列数=3、この行の列数=2` |
| 定植日を読めない | 行を飛ばす | `定植日を日付として読めないため行を飛ばしました: '<値>'` |
| ファイルを読めない（I/O エラー） | ファイルを飛ばす | `ファイルを読めないため飛ばしました: …` |

## 出力

| ファイル | 列 | 0件のとき |
|---|---|---|
| `OutputCsvFileName` | `区画コード, 作物名, 品種, 定植日`（定植日は CSV に書かれた表記のまま。前後の空白だけ除く） | 見出し行だけで作る（「該当なし」と「未実行」を区別するため） |
| `FailureCsvFileName` | `FileName, PlotCode, LineNumber, Reason, Timestamp` | 作らない（前回のファイルがあれば削除する） |

どちらも UTF-8（BOM 付き）、CRLF、全項目を引用符で囲みます。

## 結果

| 項目 | 内容 |
|---|---|
| `Outputs.OutputCsvPath` / `Outputs.FailurePath` | 出力ファイルのパス |
| `Summary.RangeStart` / `RangeEnd` | 対象期間（`yyyy-MM-dd`、終わりは含まない） |
| `Summary.InputFiles` / `ProcessedFiles` / `SkippedFiles` | 読んだファイル数、集約したファイル数、飛ばしたファイル数 |
| `Summary.Plantings` / `Failures` | 出力した行数、失敗の件数 |

## ファイル構成

| ファイル | 役割 |
|---|---|
| [LastMonthPlantingDigest.psm1](../../app/modules/LastMonthPlantingDigest/LastMonthPlantingDigest.psm1) | 読み込むファイルの一覧と公開関数 |
| [Public/Invoke-LastMonthPlantingDigestJob.ps1](../../app/modules/LastMonthPlantingDigest/Public/Invoke-LastMonthPlantingDigestJob.ps1) | ジョブコマンド |
| [Private/Records.ps1](../../app/modules/LastMonthPlantingDigest/Private/Records.ps1) | 意味を持つ見出し（作物名・品種・定植日）、出力の列、記録の形 |
| [Private/Settings.ps1](../../app/modules/LastMonthPlantingDigest/Private/Settings.ps1) | 設定の検証（必須の見出し、区画コードのグループ） |
| [Private/TextDecoding.ps1](../../app/modules/LastMonthPlantingDigest/Private/TextDecoding.ps1) | バイト列 → テキスト（BOM の判定、厳密な UTF-8、文字コードの推定） |
| [Private/DelimitedText.ps1](../../app/modules/LastMonthPlantingDigest/Private/DelimitedText.ps1) | 区切り文字の判定と、引用符・改行・行番号を扱う解析 |
| [Private/Policy.ps1](../../app/modules/LastMonthPlantingDigest/Private/Policy.ps1) | 対象期間・区画コード・見出し・定植日の規則（純粋関数） |
| [Private/FileDigest.ps1](../../app/modules/LastMonthPlantingDigest/Private/FileDigest.ps1) | 1ファイル分の集約（I/O を持たない） |
| [Private/Ports.ps1](../../app/modules/LastMonthPlantingDigest/Private/Ports.ps1) | 合成ルート（Log / Clock / Files） |
| [Private/Flow.ps1](../../app/modules/LastMonthPlantingDigest/Private/Flow.ps1) | ファイルを名前順に読み、結果と失敗一覧を出力する |

## テスト

| テスト | 内容 |
|---|---|
| [Parsing.Tests.ps1](../../tests/pester/LastMonthPlantingDigest/Parsing.Tests.ps1) | すべての BOM、厳密な UTF-8、引用符・改行・行番号、見出しの完全一致、月の境界・年の境界、定植日の形式 |
| [Digest.Tests.ps1](../../tests/pester/LastMonthPlantingDigest/Digest.Tests.ps1) | 1ファイルの集約、ファイルを飛ばす条件、実ファイルでの Flow、設定の検証 |
| [tests/e2e](../../tests/e2e/Chains.E2E.Tests.ps1) | 月次の連携で、テスト側で独立に計算した先月の定植と一致すること |

## この文書を更新するとき

- 規則・失敗の扱い・出力の列・ファイル構成が変わったとき
