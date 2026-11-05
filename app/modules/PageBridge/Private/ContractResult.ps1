# ページ契約の結果（contract result）の判定と整形。
#
# ページスクリプトは契約確認の結果を次の形で返す（app/browser/kernel/pagekit.js の contract.result）。
#   { scope, ok, fatalCount, warningCount, checks: [{ name, ok, severity, message, details }], details }
# fatal が1件でもあれば続行しない。warning は記録するが、それだけでは停止しない。

function Test-PageContractShape {
    param([AllowNull()][object]$Result)

    if ($null -eq $Result) { return $false }
    foreach ($name in @('scope', 'ok', 'fatalCount', 'warningCount', 'checks')) {
        if (-not (Test-PropertyPresent -InputObject $Result -Name $name)) { return $false }
    }

    return $true
}

function Format-PageContractResult {
    <#
    .SYNOPSIS
    契約結果を、失敗した確認項目だけを並べた複数行の文字列にする（ログ・例外メッセージ用）。
    #>
    param([Parameter(Mandatory)][object]$Result)

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("scope=$($Result.scope) ok=$($Result.ok) fatal=$($Result.fatalCount) warning=$($Result.warningCount)")

    foreach ($check in @($Result.checks)) {
        if ((Get-PropertyValue -InputObject $check -Name 'ok') -eq $true) { continue }

        $details = ''
        $checkDetails = Get-PropertyValue -InputObject $check -Name 'details'
        if ($null -ne $checkDetails) {
            $details = ' details=' + (ConvertTo-Json -InputObject $checkDetails -Compress -Depth 12)
        }

        [void]$lines.Add("[$($check.severity)] $($check.name): $($check.message)$details")
    }

    return ($lines -join [Environment]::NewLine)
}

function Assert-PageContractScope {
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][object]$Operation
    )

    if (-not (Test-PageContractShape -Result $Result)) {
        $json = ConvertTo-Json -InputObject $Result -Compress -Depth 6
        throw (New-BridgeException -Category 'configuration' -Message "操作 $($Operation.Name) の戻り値が契約結果の形ではありません: $json")
    }

    if ([string]$Result.scope -ne $Operation.Scope) {
        throw (New-BridgeException -Category 'configuration' -Message "操作 $($Operation.Name) の契約 scope が一致しません。catalog=$($Operation.Scope) page=$($Result.scope)")
    }
}

function Assert-PageContractPassed {
    <#
    .SYNOPSIS
    契約結果を判定する。warning はログに残し、fatal があれば contract 例外にする。
    #>
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][object]$Operation,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][object]$Log
    )

    Assert-PageContractScope -Result $Result -Operation $Operation

    $formatted = Format-PageContractResult -Result $Result
    if ([int]$Result.warningCount -gt 0) {
        $warn = Get-PortMember -Port $Log -PortName 'Log' -Member 'Warn'
        & $warn -Message "ページ契約の注意: $Description$([Environment]::NewLine)$formatted"
    }

    if ([int]$Result.fatalCount -gt 0) {
        throw (New-BridgeException -Category 'contract' -Message "ページ契約違反: $Description$([Environment]::NewLine)$formatted")
    }
}
