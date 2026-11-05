# 連携の1段（子ジョブ1つ）の実行と、子ジョブの結果からの値の受け取り。
#
# 子ジョブの失敗は例外として伝わるので、ここで捕まえずにそのまま連携全体を止める（後続のジョブは動かさない）。
# 結果は Jobs サービスの実装に頼らず、ここでも結果プロトコルどおりか確かめる。

function Invoke-ChainStep {
    param(
        [Parameter(Mandatory)][object]$Ports,
        [Parameter(Mandatory)][string]$JobName,
        [hashtable]$Overrides = @{}
    )

    & $Ports.Log.Section -Title "連携: $JobName を実行します"
    foreach ($key in @($Overrides.Keys | Sort-Object)) {
        & $Ports.Log.Info -Message "引き渡し: $JobName.$key = $($Overrides[$key])"
    }

    $output = @(& $Ports.Jobs.Run -JobName $JobName -Overrides $Overrides)
    $result = Assert-JobResult -Output $output -Job $JobName
    & $Ports.Log.Info -Message "連携: $JobName が正常終了しました。"
    return $result
}

function Get-ChainOutputText {
    <#
    .SYNOPSIS
    子ジョブの結果（Outputs）から、次のジョブへ渡す値を1つ読む。無い・空なら連携を止める。
    #>
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][string]$Name
    )

    $value = Get-PropertyValue -InputObject $Result.Outputs -Name $Name
    if (-not ($value -is [string]) -or [string]::IsNullOrWhiteSpace($value)) {
        throw "連携エラー: $($Result.Job) の結果に Outputs.$Name がありません。"
    }
    return $value
}
