# 出力 CSV に載せる記録の形と列順、表示用の文言（純粋関数）。
#
# 失敗記録の Code は機械的に集計できる理由の分類。PlotCode が空の行は、一覧全体に関わる失敗（件数不一致など）を表す。

$script:CsvErrorColumns = @('PlotCode', 'Owner', 'Status', 'LastMeasured', 'AnalysisRequested', 'AnalysisCompleted', 'ElapsedDays', 'Code', 'Reason', 'Timestamp')
$script:SyncFailureColumns = @('PlotCode', 'RowId', 'Owner', 'Status', 'LastMeasured', 'AnalysisRequested', 'AnalysisCompleted', 'Code', 'Reason', 'Timestamp')

function New-CsvErrorRecord {
    param(
        [Parameter(Mandatory)][object]$Record,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Reason,
        [AllowNull()][object]$ElapsedDays = $null
    )

    return [pscustomobject]@{
        PlotCode = $Record.PlotCode
        Owner = $Record.Owner
        Status = $Record.Status
        LastMeasured = $Record.LastMeasured
        AnalysisRequested = $Record.AnalysisRequested
        AnalysisCompleted = $Record.AnalysisCompleted
        ElapsedDays = $ElapsedDays
        Code = $Code
        Reason = $Reason
        Timestamp = ''
    }
}

function New-SyncFailureRecord {
    <#
    .PARAMETER Source
    失敗に関係する区画の記録（入力 CSV 由来）。一覧全体の失敗なら省略する。
    #>
    param(
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Reason,
        [AllowEmptyString()][string]$PlotCode = '',
        [AllowEmptyString()][string]$RowId = '',
        [AllowNull()][object]$Source = $null
    )

    if ([string]::IsNullOrEmpty($PlotCode) -and $null -ne $Source) { $PlotCode = [string]$Source.PlotCode }

    return [pscustomobject]@{
        PlotCode = $PlotCode
        RowId = $RowId
        Owner = [string](Get-PropertyValue -InputObject $Source -Name 'Owner' -Default '')
        Status = [string](Get-PropertyValue -InputObject $Source -Name 'Status' -Default '')
        LastMeasured = [string](Get-PropertyValue -InputObject $Source -Name 'LastMeasured' -Default '')
        AnalysisRequested = [string](Get-PropertyValue -InputObject $Source -Name 'AnalysisRequested' -Default '')
        AnalysisCompleted = [string](Get-PropertyValue -InputObject $Source -Name 'AnalysisCompleted' -Default '')
        Code = $Code
        Reason = $Reason
        Timestamp = ''
    }
}

function Get-DesiredStateLabel {
    param([Parameter(Mandatory)][bool]$Desired)

    if ($Desired) { return 'ON（土壌分析の対象）' }
    return 'OFF（土壌分析の対象外）'
}

function Get-SyncChangeLabel {
    param([Parameter(Mandatory)][object]$Result)

    if ((Get-PropertyValue -InputObject $Result -Name 'changed') -eq $true) { return '変更した' }
    if ((Get-PropertyValue -InputObject $Result -Name 'alreadyAligned') -eq $true) { return '変更不要' }
    return '目的の状態を確認した'
}
