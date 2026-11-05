# 走査後の突き合わせ（純粋関数）。CSV（計画）と画面（走査状態）の食い違いを、失敗記録として洗い出す。
#
# 1つでも失敗記録があればジョブは異常終了する。チェック操作そのものは既に終わっているため、
# 「どこが食い違ったか」を漏れなく残すことを優先し、最初の1件で止めずに全部を返す。

function Get-SoilAnalysisScanFindings {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][hashtable]$TargetIndex,
        [Parameter(Mandatory)][int]$ExpectedTotal,
        [Parameter(Mandatory)][int]$MaxLoops
    )

    $findings = New-Object System.Collections.Generic.List[object]
    $targetCount = $TargetIndex.Count

    if ($State.StopReason -eq 'loop-limit') {
        [void]$findings.Add((New-SyncFailureRecord -Code 'SCAN_LOOP_LIMIT' -Reason "走査の最大回数 $MaxLoops に達しました。未処理=$($targetCount - $State.Processed.Count) 件 画面で確認=$($State.Seen.Count) 件 画面の件数=$ExpectedTotal 件"))
    }

    foreach ($key in @($State.BadRows.Keys | Sort-Object)) {
        [void]$findings.Add((New-SyncFailureRecord -Code 'UI_ROW_WITHOUT_KEY' -Reason "区画コードか行識別子が空の行がありました: $key"))
    }

    foreach ($plotCode in @($State.Conflicts.Keys | Sort-Object)) {
        [void]$findings.Add((New-SyncFailureRecord -Code 'UI_PLOT_CODE_CONFLICT' -PlotCode $plotCode -Reason "同じ区画コードが別の行として表示されました。$($State.Conflicts[$plotCode])"))
    }

    if ($State.Seen.Count -ne $ExpectedTotal) {
        [void]$findings.Add((New-SyncFailureRecord -Code 'UI_SEEN_COUNT_MISMATCH' -Reason "画面で確認できた区画数が、画面の件数表示と一致しません。確認=$($State.Seen.Count) 件数表示=$ExpectedTotal"))
    }

    foreach ($plotCode in @($TargetIndex.Keys | Sort-Object)) {
        if (-not $State.Seen.ContainsKey($plotCode)) {
            $target = $TargetIndex[$plotCode]
            [void]$findings.Add((New-SyncFailureRecord -Code 'PLOT_NOT_FOUND_IN_UI' -Source $target.Record -Reason "CSV にある区画が一覧に見つかりません。目的=$(Get-DesiredStateLabel -Desired $target.Desired)"))
        }
    }

    foreach ($plotCode in @($State.Seen.Keys | Sort-Object)) {
        if (-not $TargetIndex.ContainsKey($plotCode)) {
            [void]$findings.Add((New-SyncFailureRecord -Code 'PLOT_NOT_IN_CSV' -PlotCode $plotCode -RowId ([string]$State.SeenRowIds[$plotCode]) -Reason '一覧にある区画が CSV にありません。CSV が最新か確認してください。'))
        }
    }

    foreach ($plotCode in @($TargetIndex.Keys | Sort-Object)) {
        if ($State.Seen.ContainsKey($plotCode) -and -not $State.Processed.ContainsKey($plotCode)) {
            $target = $TargetIndex[$plotCode]
            [void]$findings.Add((New-SyncFailureRecord -Code 'SYNC_NOT_ATTEMPTED' -Source $target.Record -Reason "一覧で見つけたが、整合を実行できませんでした。目的=$(Get-DesiredStateLabel -Desired $target.Desired)"))
        }
    }

    if ($State.Processed.Count -ne $targetCount) {
        [void]$findings.Add((New-SyncFailureRecord -Code 'PROCESSED_COUNT_MISMATCH' -Reason "整合を試みた区画数が対象件数と一致しません。処理=$($State.Processed.Count) 対象=$targetCount"))
    }

    return $findings.ToArray()
}

function Get-SoilAnalysisSuccessBreakdown {
    <#
    .SYNOPSIS
    整合に成功した結果を、目的（ON / OFF）と変更の有無で数える。
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Successes)

    return [pscustomobject]@{
        On = @($Successes | Where-Object { $_.desiredChecked -eq $true })
        Off = @($Successes | Where-Object { $_.desiredChecked -eq $false })
        Misaligned = @($Successes | Where-Object { $_.effectiveCheckedNow -ne $_.desiredChecked })
        Changed = @($Successes | Where-Object { $_.changed -eq $true })
        AlreadyAligned = @($Successes | Where-Object { $_.alreadyAligned -eq $true })
    }
}

function Get-SoilAnalysisSuccessFindings {
    param(
        [Parameter(Mandatory)][object]$Breakdown,
        [Parameter(Mandatory)][object]$Plan
    )

    $findings = New-Object System.Collections.Generic.List[object]
    $onTargets = @($Plan.Targets | Where-Object { $_.Desired }).Count
    $offTargets = @($Plan.Targets | Where-Object { -not $_.Desired }).Count

    if (@($Breakdown.On).Count -ne $onTargets) {
        [void]$findings.Add((New-SyncFailureRecord -Code 'ON_SUCCESS_COUNT_MISMATCH' -Reason "ON の成功件数が ON の対象件数と一致しません。成功=$(@($Breakdown.On).Count) 対象=$onTargets"))
    }
    if (@($Breakdown.Off).Count -ne $offTargets) {
        [void]$findings.Add((New-SyncFailureRecord -Code 'OFF_SUCCESS_COUNT_MISMATCH' -Reason "OFF の成功件数が OFF の対象件数と一致しません。成功=$(@($Breakdown.Off).Count) 対象=$offTargets"))
    }
    if (@($Breakdown.Misaligned).Count -gt 0) {
        [void]$findings.Add((New-SyncFailureRecord -Code 'SUCCESS_NOT_ALIGNED' -Reason "成功扱いなのに、操作後の状態が目的と違う区画があります。件数=$(@($Breakdown.Misaligned).Count)"))
    }

    return $findings.ToArray()
}
