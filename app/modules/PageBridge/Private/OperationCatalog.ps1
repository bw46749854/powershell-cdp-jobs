# 操作カタログ（各ジョブの PageOperations.psd1）の読み込みと検証。
#
# カタログは「PowerShell 側の操作名 → ページスクリプトのメソッド名」の対応表であり、
# 操作の種類（Kind）によって、ヘルパー未登録時の扱いと許される呼び出し方を一律に決める。
#
#   Kind      用途                         ヘルパー未登録時                     呼び出し
#   --------  ---------------------------  -----------------------------------  ---------
#   Identity  タブの画面識別               契約失敗（fatal）の結果を返す        Invoke
#   Contract  画面の契約検証               契約失敗（fatal）の結果を返す        Assert
#   Action    クリック・スクロール等       例外（helper-missing / 続行不能）   Invoke
#   Query     一覧・件数・名称の読み取り   例外（0件と未登録を混同しない）     Invoke / WaitFor
#   Probe     待機条件（真偽値）           false を返す（待機を続ける）         WaitUntil
#   Cleanup   後始末（閉じる等）           warning の結果を返す（finally を壊さない）  Invoke

$script:PageOperationKinds = @('Identity', 'Contract', 'Action', 'Query', 'Probe', 'Cleanup')

$script:PageOperationUses = @{
    Invoke = @('Identity', 'Action', 'Query', 'Cleanup')
    WaitUntil = @('Probe')
    WaitFor = @('Query')
    Assert = @('Contract')
}

$script:PageOperationKeys = @('Method', 'Kind', 'Scope', 'TimeoutSeconds', 'Label')

function Test-JavaScriptIdentifier {
    param([AllowNull()][object]$Value)

    return ($Value -is [string] -and $Value -match '^[A-Za-z_$][A-Za-z0-9_$]*$')
}

function Assert-PageOperationDefinition {
    param(
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Definition
    )

    $location = "$CatalogPath : Operations.$Name"
    if (-not ($Definition -is [hashtable])) {
        throw (New-BridgeException -Category 'configuration' -Message "操作カタログの定義は hashtable で指定してください: $location")
    }

    foreach ($key in @($Definition.Keys)) {
        if ($script:PageOperationKeys -notcontains $key) {
            throw (New-BridgeException -Category 'configuration' -Message "操作カタログに未知のキー '$key' があります（綴りを確認してください）: $location")
        }
    }

    if (-not (Test-JavaScriptIdentifier -Value $Definition['Method'])) {
        throw (New-BridgeException -Category 'configuration' -Message "Method は JavaScript の識別子で指定してください: $location")
    }

    $kind = $Definition['Kind']
    if ($script:PageOperationKinds -notcontains $kind) {
        throw (New-BridgeException -Category 'configuration' -Message "Kind は $($script:PageOperationKinds -join ' / ') のいずれかで指定してください: $location")
    }

    $needsScope = $kind -in @('Identity', 'Contract')
    $hasScope = $Definition.ContainsKey('Scope')
    if ($needsScope -and (-not ($Definition['Scope'] -is [string]) -or [string]::IsNullOrWhiteSpace($Definition['Scope']))) {
        throw (New-BridgeException -Category 'configuration' -Message "Kind=$kind の操作には Scope（契約結果の scope 名）が必要です: $location")
    }
    if (-not $needsScope -and $hasScope) {
        throw (New-BridgeException -Category 'configuration' -Message "Scope は Identity / Contract の操作にだけ指定できます: $location")
    }

    if ($Definition.ContainsKey('TimeoutSeconds')) {
        $timeout = $Definition['TimeoutSeconds']
        if (-not ($timeout -is [int]) -or $timeout -lt 1) {
            throw (New-BridgeException -Category 'configuration' -Message "TimeoutSeconds は 1 以上の整数で指定してください: $location")
        }
    }

    if ($Definition.ContainsKey('Label') -and (-not ($Definition['Label'] -is [string]) -or [string]::IsNullOrWhiteSpace($Definition['Label']))) {
        throw (New-BridgeException -Category 'configuration' -Message "Label は空でない文字列で指定してください: $location")
    }
}

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

function Get-PageOperation {
    <#
    .SYNOPSIS
    操作名から定義を取り出し、その呼び出し方（Use）が Kind に許されているか検証する。
    #>
    param(
        [Parameter(Mandatory)][object]$Catalog,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Invoke', 'WaitUntil', 'WaitFor', 'Assert')][string]$Use
    )

    if (-not $Catalog.Operations.ContainsKey($Name)) {
        throw (New-BridgeException -Category 'configuration' -Message "操作カタログに未定義の操作です: $Name（$($Catalog.Path)）")
    }

    $operation = $Catalog.Operations[$Name]
    if ($script:PageOperationUses[$Use] -notcontains $operation.Kind) {
        throw (New-BridgeException -Category 'configuration' -Message "操作 $Name（Kind=$($operation.Kind)）は $Use では呼び出せません。許可: $($script:PageOperationUses[$Use] -join ' / ')")
    }

    return $operation
}
