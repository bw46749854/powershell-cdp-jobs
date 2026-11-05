function Invoke-SoilAnalysisTargetSyncJob {
    <#
    .SYNOPSIS
    区画一覧 CSV（InputCsvPath）の判定に従い、温室コンソールの土壌分析対象チェックを ON / OFF に揃える。

    .DESCRIPTION
    「土壌分析を依頼」はクリックしない。CSV データエラーがあればブラウザに触れずに停止し、
    CSV と画面の件数・区画が食い違えばチェック操作を始めない（誤操作の防止を最優先する）。
    失敗が1件でもあれば失敗一覧を出力して異常終了する。
    #>
    param([Parameter(Mandatory)][object]$Context)

    $settings = Read-SoilAnalysisSyncSettings -Settings $Context.Settings
    $ports = New-SoilAnalysisPorts -Context $Context
    Assert-SoilAnalysisPorts -Ports $ports

    $outcome = Invoke-SoilAnalysisSyncFlow -Ports $ports -Settings $settings
    $plan = $outcome.Plan
    $successCount = 0
    if ($null -ne $outcome.Scan) { $successCount = $outcome.Scan.Successes.Count }

    return New-JobResult -Job 'SoilAnalysisTargetSync' -Outputs @{
        CsvErrorPath = $outcome.Reports.CsvErrorPath
        FailurePath = $outcome.Reports.FailurePath
    } -Summary @{
        CsvRows = @($plan.Records).Count
        OnTargets = @($plan.OnRecords).Count
        OffTargets = @($plan.OffRecords).Count
        Succeeded = $successCount
    }
}
