# 同梱した外部ツール

## Pester 5.7.1

| 項目 | 内容 |
|---|---|
| 用途 | PowerShell のテスト（`tools/Invoke-Tests.ps1` が優先して読み込む） |
| 版 | 5.7.1 |
| 入手元 | PowerShell Gallery / NuGet の公開パッケージ `Pester` 5.7.1 |
| ライセンス | Apache License 2.0（[Pester/5.7.1/LICENSE](Pester/5.7.1/LICENSE)） |
| プロジェクト | https://github.com/Pester/Pester |
| 変更 | なし（パッケージのファイルを1バイトも変えずに置いている。`.gitattributes` で改行の変換を無効にしている） |

同梱した理由は [docs/decisions/0007-vendored-test-tools.md](../../docs/decisions/0007-vendored-test-tools.md) を参照してください。

### ファイルのハッシュ（SHA-256）

更新したときは、この表を作り直してください（例: `Get-ChildItem -Recurse -File tools/vendor/Pester | Get-FileHash`）。

| ファイル | SHA-256 |
|---|---|
| `LICENSE` | `407c9c98f67f9a3979d38fec858d564018e679aecb066cbadf325b61f0cfa57e` |
| `Pester.Format.ps1xml` | `94c598f75cc09b8905e2b1c9c2c72ab000d589a317770dc6d65bc4a8df376cae` |
| `Pester.ps1` | `01b03d7ca5f727de93b65d8a2b172d1f06ef306a62915893333302aaca57bca7` |
| `Pester.psd1` | `c6dce1cdd85a9236a9a628dcaaf3e6f07b0ac4173fb25f620fa466f4402ec341` |
| `Pester.psm1` | `49e9e839447703f7b6a6a320a3c65a6dd5a17f4e33372fe02c7d32ad26a2d3ca` |
| `PesterConfiguration.Format.ps1xml` | `c270400765fe97e9933f1554ac2d78a57bba685db0bf1884869286c88034f316` |
| `bin/net452/Pester.dll` | `6c5a4c127c4dc600e746b3d6eac40ad5f28974779efcd618e0d923113f3b971d` |
| `bin/net452/Pester.pdb` | `23912407d111bb8b1ab75244cf8bfb534f5e4a7e51320444bb492821ccdb347f` |
| `bin/netstandard2.0/Pester.dll` | `fb994a81040741ca9d1f4e5b74cbad563a61f65f5af43602958be1dbae9c851f` |
| `bin/netstandard2.0/Pester.pdb` | `f526bb03c0f67733561408ddba8dd390c29516bbe321aaff4e8a0c98f1deb149` |
| `en-US/about_Pester.help.txt` | `5eb70b28e54b1000cbd9e49dded8bd9c0a8fc29364c450a1b586a6f657e57b01` |
| `en-US/about_PesterConfiguration.help.txt` | `9bd878e921fecedcdedb0cd076463aeb7a4065f34dcf614a11a8fc0880bd43e9` |
| `schemas/Cobertura/coverage-loose.dtd` | `face94d4975a0e7d01b376f9fb2fba298be61a3ca3b108799749df408d4bfefc` |
| `schemas/JUnit4/junit_schema_4.xsd` | `db8a5fc7e72267f3983a3470d4fa532a0f9349df4dad699df9e2527b40690b94` |
| `schemas/JaCoCo/report.dtd` | `7effc41ffc755dbb2f4626653753ad7d533050f1685260e219951d6e9e5a2a94` |
| `schemas/NUnit25/nunit_schema_2.5.xsd` | `19baf3e207534c770ffb6c7d470e84f22a55271f684d29f4ec34c50308d98db7` |
| `schemas/NUnit3/TestDefinitions.xsd` | `67e39db6a3251ba20a1bbdec215168b50f95c8055801652f0f760553e6120a82` |
| `schemas/NUnit3/TestFilterDefinitions.xsd` | `fbe91c35957f34e3bb2b815edd0445e9cd92dfe5fd2dd734f38b13204f59175d` |
| `schemas/NUnit3/TestResult.xsd` | `ce31e0cbd6be23c01a253570cef92c10a5689b8d184d3f3a74f2097703d3fc5b` |

### 更新の手順

1. 新しい版のパッケージを入手し、`tools/vendor/Pester/<版>/` に展開する（中身を変えない）。
2. `tools/Invoke-Tests.ps1` の読み込み先の版を更新する。
3. この文書の版とハッシュを更新する。
4. `tools\run-tests.bat`（Windows PowerShell 5.1）と `pwsh -File tools/Invoke-Tests.ps1` の両方でテスト一式を通す。
5. 古い版のフォルダーを削除する。
