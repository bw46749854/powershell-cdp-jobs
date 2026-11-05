# 一覧の走査状態（純粋関数）。画面から読んだ行を記録し、まだ整合していない対象を選び出す。
#
#   Seen        画面で見つけた区画コード（CSV に無いものも含む）
#   SeenRowIds  区画コード → 最初に見た行識別子（別の行識別子で再登場したら矛盾として記録）
#   Processed   整合を試みた区画コード（成功・失敗を問わない。同じ区画を二度操作しない）
#   BadRows     区画コードか行識別子が空の行
#   Conflicts   同じ区画コードが別の行識別子で現れたもの
#   Successes   整合に成功した結果（ページからの戻り値）
#   StopReason  complete / end-of-list / loop-limit

function New-SoilAnalysisScanState {
    return [pscustomobject]@{
        Seen = @{}
        SeenRowIds = @{}
        Processed = @{}
        BadRows = @{}
        Conflicts = @{}
        Successes = (New-Object System.Collections.Generic.List[object])
        Stall = 0
        Loops = 0
        StopReason = 'loop-limit'
    }
}

function Update-SoilAnalysisScanState {
    <#
    .SYNOPSIS
    表示中の行で走査状態を更新し、この表示範囲で整合すべき（未処理の）区画コードを名前順で返す。
    #>
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][hashtable]$TargetIndex,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$VisibleRows
    )

    $pending = @{}
    foreach ($row in $VisibleRows) {
        $plotCode = [string](Get-PropertyValue -InputObject $row -Name 'plotCode' -Default '')
        $rowId = [string](Get-PropertyValue -InputObject $row -Name 'rowId' -Default '')

        if ([string]::IsNullOrWhiteSpace($plotCode) -or [string]::IsNullOrWhiteSpace($rowId)) {
            $State.BadRows["rowId=$rowId plotCode=$plotCode"] = $true
            continue
        }

        $State.Seen[$plotCode] = $true
        if (-not $State.SeenRowIds.ContainsKey($plotCode)) {
            $State.SeenRowIds[$plotCode] = $rowId
        }
        elseif ($State.SeenRowIds[$plotCode] -ne $rowId) {
            $State.Conflicts[$plotCode] = "最初の行識別子=$($State.SeenRowIds[$plotCode]) 別の行識別子=$rowId"
        }

        if ($TargetIndex.ContainsKey($plotCode) -and -not $State.Processed.ContainsKey($plotCode)) {
            $pending[$plotCode] = $true
        }
    }

    return @($pending.Keys | Sort-Object)
}

function Test-SoilAnalysisScanComplete {
    <#
    .SYNOPSIS
    画面の件数分の区画を見つけ、かつ全対象を処理し終えたかを返す。
    #>
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][int]$ExpectedTotal,
        [Parameter(Mandatory)][int]$TargetCount
    )

    return ($State.Seen.Count -ge $ExpectedTotal -and $State.Processed.Count -ge $TargetCount)
}
