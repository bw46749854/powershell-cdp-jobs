# Lists サービス: 一部の行しか描画されない一覧（仮想スクロール）を、上から順に1行ずつ処理する。
#
#   Traverse -ExpectedCount -ReadVisible -KeyOf -Visit -ScrollNext -MaxLoops -StallLimit -EmptyMessage
#
#   1. 見えている行を読む（0行は一覧の異常としてエラー）
#   2. まだ処理していない行を Visit する（キーは KeyOf で決め、Visit が失敗しても処理済みにする）
#   3. 新しい行が無ければ下へスクロールし、少し待つ
#   4. 期待件数に達する / スクロールが StallLimit 回続けて動かない / MaxLoops に達する、のいずれかで終える
# 終了理由（StopReason）を返すだけで、件数が足りるかの判定は呼び出し側（各ジョブ）が行う。

$script:HostListsShape = @{
    Traverse = @('ExpectedCount', 'ReadVisible', 'KeyOf', 'Visit', 'ScrollNext', 'MaxLoops', 'StallLimit', 'EmptyMessage')
}

function Test-ListScrollMoved {
    param([AllowNull()][object]$ScrollResult)

    return ((Get-PropertyValue -InputObject $ScrollResult -Name 'moved') -eq $true -or
        (Get-PropertyValue -InputObject $ScrollResult -Name 'changed') -eq $true)
}

function Invoke-HostListTraversal {
    param(
        [Parameter(Mandatory)][int]$ExpectedCount,
        [Parameter(Mandatory)][scriptblock]$ReadVisible,
        [Parameter(Mandatory)][scriptblock]$KeyOf,
        [Parameter(Mandatory)][scriptblock]$Visit,
        [Parameter(Mandatory)][scriptblock]$ScrollNext,
        [Parameter(Mandatory)][int]$MaxLoops,
        [Parameter(Mandatory)][int]$StallLimit,
        [Parameter(Mandatory)][string]$EmptyMessage,
        [Parameter(Mandatory)][object]$Clock,
        [Parameter(Mandatory)][object]$Log,
        [int]$SettleMilliseconds = 700
    )

    $sleep = Get-PortMember -Port $Clock -PortName 'Clock' -Member 'Sleep'
    $info = Get-PortMember -Port $Log -PortName 'Log' -Member 'Info'
    $visited = New-Object System.Collections.Generic.List[string]
    $visitedSet = @{}
    $stall = 0
    $loops = 0
    $stopReason = 'loop-limit'

    while ($loops -lt $MaxLoops) {
        $loops++

        if ($visited.Count -ge $ExpectedCount) {
            $stopReason = 'expected-count'
            & $info -Message "期待件数 $ExpectedCount 件に達したため、一覧の走査を終えます。"
            break
        }

        $rows = @(& $ReadVisible)
        if ($rows.Count -eq 0) { throw $EmptyMessage }

        $visitedInLoop = 0
        foreach ($row in $rows) {
            $key = [string](& $KeyOf $row)
            if ([string]::IsNullOrWhiteSpace($key) -or $visitedSet.ContainsKey($key)) { continue }

            try {
                & $Visit $row
            }
            finally {
                $visitedSet[$key] = $true
                [void]$visited.Add($key)
                $visitedInLoop++
            }
        }

        if ($visitedInLoop -gt 0) { continue }

        $scrollResult = & $ScrollNext
        & $sleep -Milliseconds $SettleMilliseconds

        if (Test-ListScrollMoved -ScrollResult $scrollResult) {
            $stall = 0
            continue
        }

        $stall++
        & $info -Message "スクロール位置が変わりませんでした（$stall / $StallLimit 回）。"
        if ($stall -ge $StallLimit) {
            $stopReason = 'end-of-list'
            & $info -Message '一覧の終端に達したため、走査を終えます。'
            break
        }
    }

    return [pscustomobject]@{
        ExpectedCount = $ExpectedCount
        VisitedCount = $visited.Count
        VisitedKeys = $visited.ToArray()
        Loops = $loops
        StopReason = $stopReason
    }
}

function New-HostListService {
    param([Parameter(Mandatory)][object]$Clock, [Parameter(Mandatory)][object]$Log)

    $traverse = Get-Command -Name Invoke-HostListTraversal -CommandType Function

    return [pscustomobject]@{
        Traverse = {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)][int]$ExpectedCount,
                [Parameter(Mandatory)][scriptblock]$ReadVisible,
                [Parameter(Mandatory)][scriptblock]$KeyOf,
                [Parameter(Mandatory)][scriptblock]$Visit,
                [Parameter(Mandatory)][scriptblock]$ScrollNext,
                [Parameter(Mandatory)][int]$MaxLoops,
                [Parameter(Mandatory)][int]$StallLimit,
                [Parameter(Mandatory)][string]$EmptyMessage
            )
            & $traverse -ExpectedCount $ExpectedCount -ReadVisible $ReadVisible -KeyOf $KeyOf -Visit $Visit -ScrollNext $ScrollNext -MaxLoops $MaxLoops -StallLimit $StallLimit -EmptyMessage $EmptyMessage -Clock $Clock -Log $Log
        }.GetNewClosure()
    }
}
