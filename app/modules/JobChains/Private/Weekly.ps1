# 週次の連携: 区画一覧 CSV を出力し（PlotRosterExport）、その CSV をもとに土壌分析の対象を整合させる（SoilAnalysisTargetSync）。
#
# 受け渡すのは「出力した CSV のパス」だけ。CSV の中身は読まない（読むのは SoilAnalysisTargetSync）。
# CSV が実在しないまま後段を動かすと原因の分かりにくい入力エラーになるため、ここで存在を確かめてから渡す。

function Invoke-WeeklySoilAnalysisSyncFlow {
    param([Parameter(Mandatory)][object]$Ports)

    $export = Invoke-ChainStep -Ports $Ports -JobName 'PlotRosterExport'
    $csvPath = Get-ChainOutputText -Result $export -Name 'ExportedCsvPath'
    if (-not (& $Ports.Files.Exists -Path $csvPath)) {
        throw "連携エラー: PlotRosterExport が出力した CSV が見つかりません: $csvPath"
    }

    $sync = Invoke-ChainStep -Ports $Ports -JobName 'SoilAnalysisTargetSync' -Overrides @{ InputCsvPath = $csvPath }

    return [pscustomobject]@{
        InputCsvPath = $csvPath
        Export = $export
        Sync = $sync
    }
}
