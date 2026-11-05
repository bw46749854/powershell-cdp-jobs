Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# PageBridge: ブラウザ（Edge / Chrome）との通信と、ページ内スクリプト呼び出しの境界。
#   - CDP（Chrome DevTools Protocol）の HTTP / WebSocket 通信
#   - 操作対象タブの選択（画面識別）
#   - ページスクリプト（app/browser）の注入と、操作カタログに基づく呼び出し
#   - ページ契約（contract result）の判定
# 業務の知識（どの画面のどのボタンか）は持たない。それは各ジョブの操作カタログとページスクリプトが持つ。

$jobKitPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'JobKit/JobKit.psm1'
Import-Module -Name $jobKitPath -DisableNameChecking

foreach ($relativePath in @(
    'Private/BridgeErrors.ps1',
    'Private/CdpTransport.ps1',
    'Private/CdpSession.ps1',
    'Private/CdpRuntime.ps1',
    'Private/TargetSelection.ps1',
    'Private/OperationCatalog.ps1',
    'Private/HelperCall.ps1',
    'Private/ScriptBundle.ps1',
    'Private/ContractResult.ps1',
    'Private/PageGateway.ps1',
    'Public/PageConnection.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "PageBridge の構成ファイルが見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'New-CdpTransport',
    'Import-PageOperationCatalog',
    'Open-PageConnection',
    'Close-PageConnection',
    'Set-PageDownloadDirectory',
    'Test-PageBridgeFatalError'
)
