# 操作カタログ（各ジョブの PageOperations.psd1）を読む公開関数。
# Kind の一覧・許される呼び出し方・定義の検証は Private/OperationCatalog.ps1。

function Import-PageOperationCatalog {
    <#
    .SYNOPSIS
    操作カタログを読み込み、検証済みのカタログオブジェクトを返す。
    .OUTPUTS
    Path / Helper / Operations（操作名 → 定義） / IdentityOperation（画面識別の操作名）
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw (New-BridgeException -Category 'configuration' -Message "操作カタログが見つかりません: $Path")
    }

    $data = Import-PowerShellDataFile -LiteralPath $Path

    if (-not (Test-JavaScriptIdentifier -Value (Get-PropertyValue -InputObject $data -Name 'Helper'))) {
        throw (New-BridgeException -Category 'configuration' -Message "操作カタログの Helper は JavaScript の識別子で指定してください: $Path")
    }

    $operations = Get-PropertyValue -InputObject $data -Name 'Operations'
    if (-not ($operations -is [hashtable]) -or $operations.Count -eq 0) {
        throw (New-BridgeException -Category 'configuration' -Message "操作カタログの Operations が空、または hashtable ではありません: $Path")
    }

    $resolved = @{}
    foreach ($name in @($operations.Keys | Sort-Object)) {
        Assert-PageOperationDefinition -CatalogPath $Path -Name $name -Definition $operations[$name]
        $definition = $operations[$name]
        $resolved[$name] = [pscustomobject]@{
            Name = $name
            Method = $definition['Method']
            Kind = $definition['Kind']
            Scope = [string](Get-PropertyValue -InputObject $definition -Name 'Scope' -Default '')
            TimeoutSeconds = [int](Get-PropertyValue -InputObject $definition -Name 'TimeoutSeconds' -Default 0)
            Label = [string](Get-PropertyValue -InputObject $definition -Name 'Label' -Default $name)
        }
    }

    $identityOperations = @($resolved.Values | Where-Object { $_.Kind -eq 'Identity' })
    if ($identityOperations.Count -ne 1) {
        throw (New-BridgeException -Category 'configuration' -Message "操作カタログには Kind=Identity の操作がちょうど1つ必要です（実際: $($identityOperations.Count) 個）: $Path")
    }

    return [pscustomobject]@{
        Path = $Path
        Helper = $data['Helper']
        Operations = $resolved
        IdentityOperation = $identityOperations[0].Name
    }
}
