# はじめに

## 1. 前提

| 項目 | 内容 |
|---|---|
| OS | Windows 10 / 11 |
| PowerShell | Windows PowerShell 5.1（Windows に標準で入っている）。追加のモジュールは不要 |
| ブラウザ | Microsoft Edge または Google Chrome |
| 権限 | 管理者権限は不要 |

実行ポリシーは .bat が `-ExecutionPolicy Bypass` を付けて PowerShell を起動するため、変更しなくても動きます。

## 2. モック画面で試す

モック画面は、ジョブが対象にする2つの業務画面（温室コンソール・作付け台帳）を真似た架空の画面です。データは開いた日を基準に作られ、操作はどこにも送信されません。

1. **モック画面を配信する** — `mock\start-mock-site.bat` を実行します。http://localhost:8080/ で配信が始まり、ウィンドウを閉じるまで続きます。
2. **ブラウザを開く** — `mock\open-browser.bat` を実行します。リモートデバッグ（ポート 9222）を有効にした Edge が、専用のプロファイルで2つの画面を開きます。
3. **週次の作業を実行する** — `週次_土壌分析対象の整合.bat` を実行します。
   - 区画一覧の CSV が `work\weekly\downloads\plot_roster_MMdd.csv` に保存されます。
   - 画面の「土壌分析の対象」チェックが、CSV の判定どおりに ON / OFF に揃います（「土壌分析を依頼」は押しません）。
4. **月次の作業を実行する** — `月次_定植レポート.bat` を実行します。
   - `work\monthly\runs\yyyyMMdd_HHmmss\planting_export_downloads\` に区画ごとの作付け記録 CSV が保存されます。
   - 同じフォルダーに先月の定植をまとめた `last_month_plantings.csv` ができます。
   - モックのデータには定植日が空欄の記録が1件あるため、`last_month_plantings_failures.csv` にその行が載ります（ジョブは正常終了します）。

画面の構造を変えて試すこともできます。作付け台帳の画面上部「区画コード列の位置」を「通常列側」にしても、月次の作業は同じ結果になります（構造の違いを吸収する）。温室コンソールで「第1温室」グループを選んでから週次の作業を実行すると、画面識別に一致しないため操作を始めずに止まります（意味の違いは吸収しない）。

## 3. 本番の画面で動かす前に

1. **設定を確認する** — [configuration.md](configuration.md) を見て、`app\config\settings.psd1` の出力先・タイムアウト・判定のしきい値を確認します。
2. **ブラウザをリモートデバッグ付きで起動する** — 例:

   ```bat
   start "" msedge.exe --remote-debugging-port=9222 --user-data-dir="%LOCALAPPDATA%\powershell-cdp-jobs\edge-remote-debugging"
   ```

   普段使いのプロファイルとは別の `--user-data-dir` を指定してください。同じプロファイルのウィンドウが既に開いていると、ブラウザはデバッグ用ポートを開きません。
3. **対象の画面を開く** — 週次は温室コンソールの「区画」一覧（グループ: 全区画（既定））、月次は作付け台帳の「区画一覧」を、それぞれ1つのタブで表示します。同じ画面のタブが2つ以上あると、どちらを操作すべきか決められないため停止します。
4. **まず単独のジョブで確かめる** — 例: `powershell -NoProfile -ExecutionPolicy Bypass -File app\invoke-job.ps1 -JobName PlotRosterExport`。CSV が保存されることを確認してから連携ジョブを使います。

## 4. テストを実行する

```bat
tools\run-tests.bat
```

PowerShell のテスト（Pester 同梱）が Windows PowerShell 5.1 で動きます。ブラウザスクリプトのテストには Node.js 22 以上と、リポジトリ直下での `npm install` が必要です。詳しくは [testing.md](testing.md) を参照してください。

## この文書を更新するとき

- 起動ファイル・モック画面の使い方・前提となる環境が変わったとき
