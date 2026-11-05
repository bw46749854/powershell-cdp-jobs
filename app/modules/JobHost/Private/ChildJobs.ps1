# Jobs サービス: 連携ジョブ（JobChains）が子ジョブを起動するための窓口。
#
#   Run          -JobName -Overrides   子ジョブを実行して結果を返す
#   GetSettings  -JobName              子ジョブの設定（解決済みパス、コピー）を読む
#
# 子ジョブは「親と同じ設定ファイル・同じジョブ定義ファイル」で必ず起動する。
# パスを受け取る口を持たないことで、親子で別の設定を読む状態を構造的に起こせないようにしている。

$script:HostJobsShape = @{
    Run = @('JobName', 'Overrides')
    GetSettings = @('JobName')
}

function New-HostJobsService {
    param(
        [Parameter(Mandatory)][string]$AppRoot,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][hashtable]$Settings
    )

    $invokeHostedJob = Get-Command -Name Invoke-HostedJob -CommandType Function
    $getJobSettings = Get-Command -Name Get-HostJobSettings -CommandType Function

    return [pscustomobject]@{
        Run = {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$JobName, [hashtable]$Overrides = @{})
            & $invokeHostedJob -AppRoot $AppRoot -JobName $JobName -SettingsPath $SettingsPath -CatalogPath $CatalogPath -SettingsOverrides $Overrides
        }.GetNewClosure()
        GetSettings = {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$JobName)
            & $getJobSettings -Settings $Settings -JobName $JobName -ProjectRoot $ProjectRoot
        }.GetNewClosure()
    }
}
