Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# JobKit: ジョブと実行基盤が共有する「純粋な」約束事（ポートの形、ジョブ結果、設定値の読み方）。
# I/O・時刻・ブラウザには一切触れない。どのモジュールからも依存してよい唯一の共有モジュール。

foreach ($relativePath in @(
    'Public/Values.ps1',
    'Public/Ports.ps1',
    'Public/JobResults.ps1',
    'Public/Settings.ps1',
    'Public/Steps.ps1'
)) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) { throw "JobKit の構成ファイルが見つかりません: $path" }
    . $path
}

Export-ModuleMember -Function @(
    'Get-PropertyValue',
    'Test-PropertyPresent',
    'Get-PortMember',
    'Get-ScriptBlockParameterNames',
    'Assert-PortShape',
    'New-JobResult',
    'Assert-JobResult',
    'Read-JobSetting',
    'Invoke-LoggedStep'
)
