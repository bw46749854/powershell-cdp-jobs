# ポート = 「scriptblock をメンバーに持つオブジェクト」。ジョブは外部 I/O をすべてポート経由で使う。
# 本番実装とテスト用の偽物が同じ形であることを、メンバー名と宣言パラメーター名で検証する。

function Get-PortMember {
    <#
    .SYNOPSIS
    ポートから scriptblock のメンバーを取り出す。無ければポート名とメンバー名を含む例外にする。
    #>
    param(
        [AllowNull()][object]$Port,
        [Parameter(Mandatory)][string]$PortName,
        [Parameter(Mandatory)][string]$Member
    )

    $value = Get-PropertyValue -InputObject $Port -Name $Member
    if (-not ($value -is [scriptblock])) {
        throw "ポート '$PortName' に scriptblock のメンバー '$Member' がありません。"
    }

    return $value
}

function Get-ScriptBlockParameterNames {
    <#
    .SYNOPSIS
    scriptblock の param ブロックで宣言されたパラメーター名を返す（param ブロックが無ければ空）。
    #>
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock)

    $paramBlock = $ScriptBlock.Ast.ParamBlock
    if ($null -eq $paramBlock) { return @() }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($parameter in $paramBlock.Parameters) {
        [void]$names.Add($parameter.Name.VariablePath.UserPath)
    }

    return $names.ToArray()
}

function Assert-PortShape {
    <#
    .SYNOPSIS
    ポートが「必要なメンバー」と「各メンバーの必須パラメーター名」を満たしているか検証する。
    .PARAMETER Members
    メンバー名 → そのメンバーが宣言しているべきパラメーター名の配列。
    余分なメンバーや余分なパラメーターは許容する（使う側が必要とする形だけを要求する）。
    #>
    param(
        [AllowNull()][object]$Port,
        [Parameter(Mandatory)][string]$PortName,
        [Parameter(Mandatory)][hashtable]$Members
    )

    if ($null -eq $Port) {
        throw "ポート '$PortName' が指定されていません。"
    }

    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($memberName in @($Members.Keys | Sort-Object)) {
        $value = Get-PropertyValue -InputObject $Port -Name $memberName
        if (-not ($value -is [scriptblock])) {
            [void]$problems.Add("$memberName は scriptblock ではありません")
            continue
        }

        $declared = @(Get-ScriptBlockParameterNames -ScriptBlock $value)
        foreach ($requiredName in @($Members[$memberName])) {
            if ($declared -notcontains $requiredName) {
                [void]$problems.Add("$memberName にパラメーター -$requiredName が宣言されていません")
            }
        }
    }

    if ($problems.Count -gt 0) {
        throw "ポート '$PortName' の形が契約と一致しません: $($problems -join ' / ')"
    }
}
