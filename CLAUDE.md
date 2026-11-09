# CLAUDE.md

Windows PowerShell 5.1 から Chrome DevTools Protocol でブラウザを操作し、架空の温室運用の定型作業を自動化するジョブ群です。全体像は README.md と ARCHITECTURE.md を読んでください。

## 必ず守ること

- 規約: docs/guides/maintenance-rules.md（不変条件・構造の整理をするかの判定・進め方・提案の形）
- 判断の基準: docs/guides/design-principles.md
- 変更内容ごとの直す場所: docs/guides/making-changes.md
- 本番は Windows PowerShell 5.1。5.1 で使えない書き方は docs/guides/powershell-compatibility.md を見る
- PowerShell のソースは UTF-8（BOM 付き）・LF、.bat は ASCII・CRLF。崩したら tools/Repair-SourceEncoding.ps1 で直す

## テスト

- 一式: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\Invoke-Tests.ps1`（Windows PowerShell 5.1）。PowerShell 7 なら `pwsh -File tools/Invoke-Tests.ps1`
- ブラウザスクリプトだけ: `npm test`（初回は `npm install`）
- 変更したら、5.1 で通したかどうかを必ず報告する

## 文書

- 文書の地図は docs/README.md。コードを直したら、対応する文書の「この文書を更新するとき」に従って同じ変更で直す
- 文書の網羅とリンクは tests/pester/Quality/Documentation.Tests.ps1 が検査する
