# 0007. テスト用の Pester を同梱する

- 状態: 採用
- 日付: 2026-11-05

## 状況

Windows PowerShell 5.1 には古い Pester 3 が標準で入っていますが、テストは Pester 5 の書き方です。業務用の PC では PowerShell ギャラリーからモジュールをインストールできないことがあり、テストを実行できる PC が限られます。

## 判断

- Pester 5.7.1 を `tools/vendor/Pester/5.7.1` に、公開されているパッケージのファイルを1バイトも変えずに置きます（[tools/vendor/README.md](../../tools/vendor/README.md)）。
- `tools/Invoke-Tests.ps1` は同梱の Pester を優先して読み込み、無ければインストール済みの 5.5 以上を使います。
- 同梱したファイルは署名付きのため、git の改行の変換を無効にします（`.gitattributes` の `tools/vendor/** -text`）。文字コードの整形・品質ゲートの対象からも外します。

## 理由と結果

- リポジトリを取得するだけで、どの PC でも同じ版の Pester でテストできます。
- Pester を更新するときは、パッケージを入れ替えて `tools/vendor/README.md` の版とハッシュを更新し、テスト一式を通します。

## 検討した他の案

- **テストのたびに Install-Module する**: ネットワークと権限に依存し、版も揃いません。
- **Pester 3 の書き方に合わせる**: 古い書き方で、BeforeAll / TestCases / TestDrive などの機能が限られます。
