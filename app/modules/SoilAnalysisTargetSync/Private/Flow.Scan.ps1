# 処理の順序（走査）: 一覧を上から順に表示し、見えている対象区画を1件ずつ目的の状態に揃える。
#
# 区画ごとの失敗は失敗記録にして走査を続ける。ただしブラウザとの通信を続けられない失敗
# （セッション切断・通信タイムアウト・ページヘルパー消失）は、続けても全件失敗するだけなので即座に停止する。

function Invoke-SoilAnalysisPlotSync {
    <#
    .SYNOPSIS
    1区画を目的の状態に揃え、結果（成功 / 失敗記録 / 続行不能か）を返す。
    #>
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Target
    )

    $log = $Ports.Log
    $label = Get-DesiredStateLabel -Desired $Target.Desired

    try {
        $result = & $Ports.Page.SyncSelection -PlotCode $Target.PlotCode -Desired $Target.Desired
    }
    catch {
        $message = $_.Exception.Message
        & $log.Warn -Message "整合NG: $($Target.PlotCode) / 目的=$label / 例外=$message"
        return [pscustomobject]@{
            Ok = $false
            Fatal = [bool](& $Ports.Page.IsFatal -ErrorObject $_)
            Result = $null
            Failure = New-SyncFailureRecord -Code 'SYNC_EXCEPTION' -Source $Target.Record -Reason "整合中に例外が発生しました。目的=$label / 詳細=$message"
        }
    }

    if ((Get-PropertyValue -InputObject $result -Name 'ok') -eq $true) {
        & $log.Info -Message "整合OK: $($Target.PlotCode) / 目的=$label / 結果=$(Get-SyncChangeLabel -Result $result) / 理由=$($Target.Reason)"
        return [pscustomobject]@{ Ok = $true; Fatal = $false; Result = $result; Failure = $null }
    }

    $reason = [string](Get-PropertyValue -InputObject $result -Name 'reason' -Default 'unknown')
    $details = ConvertTo-Json -InputObject $result -Compress -Depth 8
    & $log.Warn -Message "整合NG: $($Target.PlotCode) / 目的=$label / 画面の理由=$reason"
    return [pscustomobject]@{
        Ok = $false
        Fatal = $false
        Result = $result
        Failure = New-SyncFailureRecord -Code 'SYNC_FAILED' -Source $Target.Record -RowId ([string](Get-PropertyValue -InputObject $result -Name 'rowId' -Default '')) -Reason "チェックを目的の状態にできませんでした。目的=$label / 画面の理由=$reason / 詳細=$details"
    }
}

function Invoke-SoilAnalysisScan {
    <#
    .SYNOPSIS
    一覧を走査して対象を揃え、走査状態（ScanState.ps1）を返す。
    #>
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][object]$Settings,
        [Parameter(Mandatory)][hashtable]$TargetIndex,
        [Parameter(Mandatory)][int]$ExpectedTotal,
        [Parameter(Mandatory)][object]$Ledger
    )

    $page = $Ports.Page
    $log = $Ports.Log
    $state = New-SoilAnalysisScanState

    while ($state.Loops -lt $Settings.MaxScanLoops) {
        $state.Loops++
        $visible = @(& $page.ReadVisibleRows)
        $pending = @(Update-SoilAnalysisScanState -State $state -TargetIndex $TargetIndex -VisibleRows $visible)

        foreach ($plotCode in $pending) {
            if ($state.Processed.ContainsKey($plotCode)) { continue }

            $outcome = Invoke-SoilAnalysisPlotSync -Ports $Ports -Target $TargetIndex[$plotCode]
            $state.Processed[$plotCode] = $true

            if ($outcome.Ok) {
                [void]$state.Successes.Add($outcome.Result)
                continue
            }

            Add-SoilAnalysisFailure -Ledger $Ledger -Failures @($outcome.Failure)
            if ($outcome.Fatal) {
                throw "ブラウザとの通信を続けられないため停止します。区画=$plotCode / $($outcome.Failure.Reason)"
            }
        }

        if (Test-SoilAnalysisScanComplete -State $state -ExpectedTotal $ExpectedTotal -TargetCount $TargetIndex.Count) {
            $state.StopReason = 'complete'
            & $log.Info -Message "走査完了: 一覧で $($state.Seen.Count)/$ExpectedTotal 件を確認し、$($state.Processed.Count)/$($TargetIndex.Count) 件を処理しました。"
            break
        }

        $scroll = & $page.ScrollDown
        if ((Get-PropertyValue -InputObject $scroll -Name 'changed') -eq $true) {
            $state.Stall = 0
            continue
        }

        $state.Stall++
        if ($state.Stall -ge $Settings.StallLimit) {
            $state.StopReason = 'end-of-list'
            & $log.Info -Message '一覧の終端に達したため、走査を終えます。'
            break
        }
    }

    return $state
}
