# ジョブ結果プロトコル。
# すべてのジョブコマンドは「New-JobResult で作った結果オブジェクトを1つだけ」返す。
# 実行基盤は Assert-JobResult で検証し、連携ジョブは Outputs だけを読んで次のジョブへ渡す。
# 失敗は結果ではなく例外で表す（Ok = $false の結果は返さない）。

function New-JobResult {
    <#
    .SYNOPSIS
    ジョブの成功結果を作る。Outputs は後続ジョブが使う成果物、Summary は件数などの記録。
    #>
    param(
        [Parameter(Mandatory)][string]$Job,
        [hashtable]$Outputs = @{},
        [hashtable]$Summary = @{}
    )

    return [pscustomobject]@{
        Job = $Job
        Ok = $true
        Outputs = [pscustomobject]$Outputs
        Summary = [pscustomobject]$Summary
    }
}

function Assert-JobResult {
    <#
    .SYNOPSIS
    ジョブコマンドの出力が結果プロトコルどおりか検証し、結果オブジェクトを返す。
    .DESCRIPTION
    パイプラインへの出力漏れ（[void] の付け忘れ等）があると複数オブジェクトになるため、
    「ちょうど1つ」を要求して早期に検出する。
    #>
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Output,
        [Parameter(Mandatory)][string]$Job
    )

    $items = @($Output | Where-Object { $null -ne $_ })
    if ($items.Count -ne 1) {
        throw "ジョブ '$Job' は結果オブジェクトを1つだけ返す必要があります（実際: $($items.Count) 個）。"
    }

    $result = $items[0]
    foreach ($name in @('Job', 'Ok', 'Outputs', 'Summary')) {
        if (-not (Test-PropertyPresent -InputObject $result -Name $name)) {
            throw "ジョブ '$Job' の結果に $name がありません。New-JobResult で結果を作成してください。"
        }
    }

    if ([string]$result.Job -ne $Job) {
        throw "ジョブ '$Job' の結果に別のジョブ名 '$($result.Job)' が設定されています。"
    }

    if (-not ($result.Ok -is [bool]) -or -not $result.Ok) {
        throw "ジョブ '$Job' が成功以外の結果を返しました。失敗は例外で通知してください。"
    }

    return $result
}
