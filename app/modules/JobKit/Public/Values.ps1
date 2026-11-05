# hashtable と pscustomobject（ConvertFrom-Json の結果を含む）を同じ書き方で安全に読むための関数群。
# ブラウザから返る結果は項目が欠けることがあるため、「無い」を例外にせず既定値で表現する。

function Test-PropertyPresent {
    <#
    .SYNOPSIS
    hashtable のキー、またはオブジェクトのプロパティが存在するかを返す。
    #>
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $false }
    if ($InputObject -is [System.Collections.IDictionary]) { return [bool]$InputObject.Contains($Name) }
    return ($null -ne $InputObject.PSObject.Properties[$Name])
}

function Get-PropertyValue {
    <#
    .SYNOPSIS
    hashtable のキー、またはオブジェクトのプロパティを読む。存在しなければ Default を返す。
    .NOTES
    配列値は PowerShell の仕様で展開されるため、配列を期待する呼び出し側は @() で受けること。
    #>
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if (-not (Test-PropertyPresent -InputObject $InputObject -Name $Name)) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) { return $InputObject[$Name] }
    return $InputObject.PSObject.Properties[$Name].Value
}
