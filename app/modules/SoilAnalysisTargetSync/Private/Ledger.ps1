# 実行台帳: この実行で見つかった CSV データエラーと失敗記録を集め、出力済みかどうかを持つ。
# 記録時刻は Clock ポートから取る（テストでは固定の時計を使う）。

function New-SoilAnalysisLedger {
    param([Parameter(Mandatory)][object]$Clock)

    return [pscustomobject]@{
        Clock = $Clock
        CsvErrors = (New-Object System.Collections.Generic.List[object])
        Failures = (New-Object System.Collections.Generic.List[object])
        Exported = $false
    }
}

function Get-SoilAnalysisLedgerTimestamp {
    param([Parameter(Mandatory)][object]$Ledger)

    return ([datetime](& (Get-PortMember -Port $Ledger.Clock -PortName 'Clock' -Member 'Now'))).ToString('yyyy-MM-dd HH:mm:ss')
}

function Add-SoilAnalysisFailure {
    param(
        [Parameter(Mandatory)][object]$Ledger,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Failures
    )

    foreach ($failure in $Failures) {
        if ([string]::IsNullOrEmpty($failure.Timestamp)) { $failure.Timestamp = Get-SoilAnalysisLedgerTimestamp -Ledger $Ledger }
        [void]$Ledger.Failures.Add($failure)
    }
}

function Add-SoilAnalysisCsvError {
    param(
        [Parameter(Mandatory)][object]$Ledger,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$CsvErrors
    )

    foreach ($csvError in $CsvErrors) {
        if ([string]::IsNullOrEmpty($csvError.Timestamp)) { $csvError.Timestamp = Get-SoilAnalysisLedgerTimestamp -Ledger $Ledger }
        [void]$Ledger.CsvErrors.Add($csvError)
    }
}

function Test-SoilAnalysisLedgerClean {
    param([Parameter(Mandatory)][object]$Ledger)

    return ($Ledger.Failures.Count -eq 0 -and $Ledger.CsvErrors.Count -eq 0)
}
