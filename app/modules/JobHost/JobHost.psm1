Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# JobHost: ジョブの実行基盤。
#   - 設定（settings.psd1）とジョブ定義（jobs.psd1）の読み込みと検証
#   - 実行コンテキスト（Context）とサービス（Log / Files / Downloads / Lists / Clock / Browser / Jobs）の組み立て
#   - ジョブコマンドの呼び出しと、結果プロトコルの検証、後始末
# 各ジョブは Context.Services だけを通して外部 I/O を使う。ジョブ固有の業務知識はここに置かない。

$modulesRoot = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path $modulesRoot 'JobKit/JobKit.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $modulesRoot 'PageBridge/PageBridge.psm1') -DisableNameChecking

foreach ($relativePath in @(
    'Private/HostPaths.ps1',
    'Private/HostSettings.ps1',
    'Private/JobCatalog.ps1',
    'Private/HostClock.ps1',
    'Private/HostLog.ps1',
    'Private/SafePaths.ps1',
    'Private/CsvText.ps1',
    'Private/FileService.ps1',
    'Private/DownloadWatcher.ps1',
    'Private/ListTraversal.ps1',
    'Private/BrowserService.ps1',
    'Private/ChildJobs.ps1',
    'Private/RunContext.ps1',
    'Public/Invoke-HostedJob.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "JobHost の構成ファイルが見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'Invoke-HostedJob'
)
