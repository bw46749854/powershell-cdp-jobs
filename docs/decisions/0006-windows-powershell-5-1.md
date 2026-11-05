# 0006. 本番は Windows PowerShell 5.1

- 状態: 採用
- 日付: 2026-11-05

## 状況

ジョブを動かす PC は、業務用に管理された Windows です。ソフトウェアの追加インストール（PowerShell 7、ブラウザ操作のライブラリ、Python など）には申請と時間がかかり、PC によって状況が異なります。

## 判断

- 本番の実行環境は、Windows に標準で入っている **Windows PowerShell 5.1** とします。PowerShell 7 でも動くように書きますが、基準は 5.1 です。
- ブラウザの操作には、Edge / Chrome が標準で持つ **Chrome DevTools Protocol** を使い、.NET の HttpClient と ClientWebSocket で直接通信します。外部のライブラリは使いません。
- PowerShell 7 専用の構文・コマンド・パラメーター・.NET API を使いません。ソースは BOM 付き UTF-8 で保存します。これらはテストで検査します（[guides/powershell-compatibility.md](../guides/powershell-compatibility.md)）。

## 理由と結果

- 追加のインストール無しで、どの業務用 PC でも同じように動きます。
- 5.1 の制約（BOM、配列の展開、`GetNewClosure` の見え方など）に合わせた書き方が必要です。約束を文書にまとめ、テストで機械的に確かめます。
- CDP の通信・待機・エラーの分類を自前で持つため、その部分（PageBridge）を偽のトランスポートで丁寧にテストします。

## 検討した他の案

- **PowerShell 7 を前提にする**: 書きやすくなりますが、インストールの手間と PC ごとの差が残ります。
- **Selenium / WebDriver、Playwright などのブラウザ操作ライブラリ**: ドライバやランタイムのインストールと、ブラウザの版との対応の管理が必要です。
