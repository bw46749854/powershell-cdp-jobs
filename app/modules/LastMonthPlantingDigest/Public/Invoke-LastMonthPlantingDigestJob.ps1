function Invoke-LastMonthPlantingDigestJob {
    <#
    .SYNOPSIS
    区画ごとの作付け記録 CSV（TargetDirectory）から「先月に定植した作付け」を集め、1つの CSV にまとめる。

    .DESCRIPTION
    ブラウザは使わない。ファイル・行の問題は失敗一覧 CSV に残して処理を続け、ジョブ自体は正常終了する
    （集計結果と失敗一覧を担当者が確認する運用）。
    #>
    param([Parameter(Mandatory)][object]$Context)

    $settings = Read-PlantingDigestSettings -Settings $Context.Settings
    $ports = New-PlantingDigestPorts -Context $Context
    Assert-PlantingDigestPorts -Ports $ports

    $outcome = Invoke-PlantingDigestFlow -Ports $ports -Settings $settings

    return New-JobResult -Job 'LastMonthPlantingDigest' -Outputs @{
        OutputCsvPath = $outcome.OutputPath
        FailurePath = $outcome.FailurePath
    } -Summary @{
        RangeStart = $outcome.Range.StartInclusive.ToString('yyyy-MM-dd')
        RangeEnd = $outcome.Range.EndExclusive.ToString('yyyy-MM-dd')
        InputFiles = $outcome.InputFileCount
        ProcessedFiles = $outcome.ProcessedFileCount
        SkippedFiles = $outcome.SkippedFileCount
        Plantings = @($outcome.Rows).Count
        Failures = @($outcome.Failures).Count
    }
}
